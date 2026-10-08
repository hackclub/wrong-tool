require "test_helper"

class LeaderboardsControllerTest < ActionDispatch::IntegrationTest
  test "without a project, it's back to onboarding" do
    get leaderboard_path
    assert_redirected_to onboarding_path
  end

  test "you're not on it until you're set up" do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path(sort: "streak")

    assert_response :success
    assert_select "tr[data-you] td", "—"
    assert_select ".formula-bar__content", /=RANK\(you, streak\) → #N\/A/
  end

  test "set up, you're ranked" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get leaderboard_path

    assert_select "tr[data-you] .leaderboard__rank", "1"
    assert_select "tr[data-you]", /0 hrs/
    assert_select ".leaderboard__note", "Most hours built this week."
    assert_select ".leaderboard__change", false, "no arrows without a snapshot"
    assert_select ".formula-bar__content", /=RANK\(you, week_hours\) → 1/

    projects(:orpheus).update!(week_rank: 3, week_rank_on: Date.current)
    get leaderboard_path
    assert_select "tr[data-you] .leaderboard__change[data-direction=up]", "▲2"
    get leaderboard_path(sort: "streak")
    assert_select ".leaderboard__change", false, "arrows are for the week board"
  end
end
