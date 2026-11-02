require "test_helper"

class Review::ClaimsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = []
    users(:ana).update!(review_roles: [ "reviewer" ])
    users(:orpheus).update!(review_roles: [ "reviewer" ])
    @heidi = User.create!(hca_id: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi", slack_id: "U0HEIDI")
    @heidi_project = Project.create!(user: @heidi, tool: "email", tool_name: "Email", idea: "a maze", prize: "miyoo", pace_minutes: 45,
                                     build_time: "evening", signed_on: Date.new(2026, 10, 1))
    travel_to(Time.utc(2026, 11, 2, 10)) { @first = ship_for(@heidi_project, "Inbox Maze") }
    travel_to(Time.utc(2026, 11, 2, 11)) { @second = ship_for(@heidi_project, "Inbox Maze 2") }
    travel_to(Time.utc(2026, 11, 2, 12)) { @third = ship_for(projects(:ana), "Pong in Figma") }
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "opening a ship claims it: anyone else sees it read-only, and can't decide it" do
    sign_in_as(users(:orpheus))
    get review_ship_path(@first)
    assert_select ".review__claim[data-claimed=mine][data-controller=review-claim][data-review-claim-url-value=?]", review_ship_claim_path(@first)
    assert_select "form[action=?]", review_ship_decisions_path(@first)

    sign_in_as(users(:ana))
    get review_ship_path(@first)
    assert_select ".review__claim[data-claimed=other]", /Orpheus is on this one, since \d\d:\d\d UTC/
    assert_select "form[action=?]", review_ship_decisions_path(@first), 0
    assert_select "form[action=?]", review_ship_claim_path(@first), 0, "only admins take over"
    post review_ship_decisions_path(@first), params: { review: { decision: "rejected", note_to_maker: "Sneaking a decision in." } }
    assert_response :unprocessable_entity
    assert @first.reload.in_review?

    get review_root_path
    assert_select "tr##{dom_id(@first)} [data-claimed]", "Orpheus is on it"
    assert_select "tr##{dom_id(@second)} [data-claimed]", 0
  end

  test "you hold one at a time; the page keeps it alive, and it goes once it's idle" do
    sign_in_as(users(:orpheus))
    get review_ship_path(@first)
    get review_ship_path(@second)
    assert_equal [ @second ], ReviewClaim.where(user: users(:orpheus)).map(&:ship), "opening another lets the first go"

    travel 20.minutes do
      patch review_ship_claim_path(@second)
      assert_response :no_content
    end

    travel 45.minutes do
      sign_in_as(users(:ana))
      get review_ship_path(@second)
      assert_select ".review__claim[data-claimed=other]", 1, "Orpheus beat 25 minutes ago: still his"
    end

    travel 55.minutes do
      sign_in_as(users(:ana))
      get review_ship_path(@second)
      assert_select ".review__claim[data-claimed=mine]", 1, "idle for 35 minutes, so it's Ana's"

      sign_in_as(users(:orpheus))
      patch review_ship_claim_path(@second)
      assert_response :conflict, "his page hears it's gone"
    end
  end

  test "an admin takes over" do
    sign_in_as(users(:ana))
    get review_ship_path(@first)

    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    sign_in_as(users(:orpheus))
    get review_ship_path(@first)
    assert_select ".review__claim[data-claimed=other]", /Ana is on this one/
    post review_ship_claim_path(@first)
    assert_redirected_to review_ship_path(@first)
    follow_redirect!
    assert_select ".review__claim[data-claimed=mine]"
    assert_equal users(:orpheus), ReviewClaim.find_by(ship: @first).user
  end

  test "deciding goes on to the next in line, past anyone else's and your own, and skip passes one over" do
    sign_in_as(users(:ana))
    get review_ship_path(@second) # Ana's on the second

    sign_in_as(users(:orpheus))
    post review_next_path
    assert_redirected_to review_ship_path(@first), "first in line"

    post review_ship_decisions_path(@first), params: { review: { decision: "changes_requested", note_to_maker: "The maze has no exit." } }
    assert_redirected_to review_ship_path(@third), "past the second (Ana's on it)"
    assert_equal "Inbox Maze: asked for changes. Next up.", flash[:notice]
    assert_nil ReviewClaim.find_by(ship: @first), "decided, so let go"

    post review_next_path, params: { after: @third.id, skip: 1 }
    assert_redirected_to review_root_path, "the third's skipped, the second's Ana's: nothing left"
    assert_equal "Nothing else is waiting on you.", flash[:notice]

    get review_root_path # back at the queue: skips forgotten
    post review_next_path
    assert_redirected_to review_ship_path(@third)

    sign_in_as(users(:ana))
    post review_next_path, params: { after: @second.id, skip: 1 }
    assert_redirected_to review_root_path, "her own ship never comes up, and Orpheus has the third"
  end

  private
    def ship_for(project, title)
      project.ships.create!(title:, description: "A game you play by sending emails to a robot that answers in riddles.",
                            repo_url: "https://github.com/someone/game", demo_url: "https://example.com/game", hours: 4,
                            screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
    end

    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
