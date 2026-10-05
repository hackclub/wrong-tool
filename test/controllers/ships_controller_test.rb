require "test_helper"

class ShipsControllerTest < ActionDispatch::IntegrationTest
  test "shipping opens once you're set up" do
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

  test "shipping, then it's in review" do
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

  test "what a ship's missing says so" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as_orpheus
    post project_ship_path, params: { ship: ship_params.merge(description: "short", screenshot_shows_game: "0") }

    assert_response :unprocessable_entity
    assert_select ".ship__error", /Description needs at least 40 characters/
    assert_select ".ship__error", /has to show the game running/
  end

  private
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
