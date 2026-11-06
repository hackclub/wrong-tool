require "test_helper"

class ShipsControllerTest < ActionDispatch::IntegrationTest
  test "shipping opens once you're set up" do
    while_shipping_is_open do
      get project_ship_path
      assert_redirected_to onboarding_path

      sign_in_as_orpheus
      get project_ship_path
      assert_redirected_to project_path

      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      get project_ship_path
      assert_response :success
      assert_select "input#ship_title[value='A rhythm game in Spreadsheet']"
      assert_select ".ship__hackatime-name", "rhythm-game"
    end
  end

  test "shipping, then it's in review" do
    while_shipping_is_open do
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      sign_in_as_orpheus

      post project_ship_path, params: { ship: ship_params }
      assert_redirected_to project_ship_path
      assert_equal "congratulate", flash[:clippy]
      follow_redirect!
      assert_select ".ship__done-title", "Shipped."
      assert_select ".ship__done-text", /Beat Sheet is in review/

      assert_no_difference -> { Ship.count } do
        post project_ship_path, params: { ship: ship_params }
      end
      get project_path
      assert_select ".project__ship", /In review/
    end
  end

  test "without your address, shipping waits for it: shared through Hack Club" do
    while_shipping_is_open do
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      sign_in_as_orpheus
      users(:orpheus).update!(address: nil) # signed in before we asked

      get project_ship_path
      assert_select ".ship__done[data-state=address] .ship__done-title", "First, your address."
      assert_select "form[action='/auth/hackclub'] input[name=origin][value=?]", project_ship_path
      assert_select "form.ship__form", 0
      assert_no_difference -> { Ship.count } do
        post project_ship_path, params: { ship: ship_params }
      end

      users(:orpheus).update!(address: HQ_ADDRESS)
      get project_ship_path
      assert_select "form.ship__form"
    end
  end

  test "what a ship's missing says so" do
    while_shipping_is_open do
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      sign_in_as_orpheus
      post project_ship_path, params: { ship: ship_params.merge(description: "short", screenshot_shows_game: "0") }

      assert_response :unprocessable_entity
      assert_select ".ship__error", /Description needs at least 40 characters/
      assert_select ".ship__error", /has to show the game running/
    end
  end

  test "never shipped, shipping stays open past the quiet days through last call, then closes" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    users(:orpheus).update!(timezone: "America/New_York")
    sign_in_as_orpheus

    travel_to Time.utc(2026, 10, 30, 3) do # 11pm on Oct 29 in New York: still open
      get project_ship_path
      assert_select "form.ship__form"
      get project_path
      assert_select ".project__ship", /Ship/
    end

    travel_to Time.utc(2026, 11, 6, 4) do # 11pm on Nov 5 in New York: last call, still open
      get project_ship_path
      assert_select "form.ship__form"
    end

    travel_to Time.utc(2026, 11, 6, 6) do
      get project_ship_path
      assert_response :success
      assert_select ".ship__done[data-state=closed] .ship__done-title", "Shipping's closed."
      assert_select ".ship__done-text", /was Oct 27\./
      assert_select ".ship__done-text", { text: /Oct 29/, count: 0 }, "the grace is never mentioned"
      assert_select "form.ship__form", 0
      assert_no_difference -> { Ship.count } do
        post project_ship_path, params: { ship: ship_params }
      end
      assert_redirected_to project_ship_path
      get project_path
      assert_select ".project__ship", 0
    end
  end

  test "asked for changes, it opens again with what to change and what you shipped, even after it's all closed" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    while_shipping_is_open { post project_ship_path, params: { ship: ship_params } }
    ship = projects(:orpheus).ship_in_review

    travel_to Time.utc(2026, 11, 20, 12) do
      ship.update!(status: "changes_requested", decided_at: Time.current)
      ship.review_decisions.create!(decision: "changes_requested", note_to_maker: "The demo asks me to sign in.")

      get project_ship_path
      assert_select ".ship__changes", /A reviewer asked for changes\..*ship it again by\s+Nov 27/m
      assert_select ".ship__changes .ship__note", "The demo asks me to sign in."
      assert_select "textarea#ship_description", /every beat is a cell/
      assert_select "input#ship_demo_url[value='https://example.com/beat']"

      assert_difference -> { Ship.count } do
        post project_ship_path, params: { ship: ship_params.merge(demo_url: "https://example.com/beat-public") }
      end
      assert projects(:orpheus).ship_in_review
      get project_ship_path
      assert_select ".ship__done-title", "Shipped."
    end
  end

  test "rejected, it says why and never opens again" do
    while_shipping_is_open do
      link_hackatime(users(:orpheus))
      projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
      sign_in_as_orpheus
      post project_ship_path, params: { ship: ship_params }
      ship = projects(:orpheus).ship_in_review
      ship.update!(status: "rejected", decided_at: Time.current)
      ship.review_decisions.create!(decision: "rejected", note_to_maker: "This is someone else's game.")

      get project_ship_path
      assert_select ".ship__done[data-state=rejected] .ship__done-title", "Not approved."
      assert_select ".ship__note", "This is someone else's game."
      assert_select "form.ship__form", 0
      assert_no_difference -> { Ship.count } do
        post project_ship_path, params: { ship: ship_params }
      end
    end
  end

  private
    # Mid-program, when shipping's open (it closed for good after last call, Program::LAST_CALL_THROUGH), whatever
    # today is.
    def while_shipping_is_open(&)
      travel_to(Time.utc(2026, 10, 20, 12), &)
    end

    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end

    def ship_params
      { title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
        repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
        screenshot: fixture_file_upload("screenshot.png", "image/png"), screenshot_shows_game: "1" }
    end
end
