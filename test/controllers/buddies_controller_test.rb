require "test_helper"

class BuddiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    post "/auth/hackclub"
    follow_redirect!
  end

  test "before you're paired: how it works, and your invite link" do
    get buddy_path

    assert_select "h1", "Build with a buddy"
    assert_equal [ "Both log 4h a week", "Playtest each other", "Cover a bad week" ], css_select(".buddy-rules__title").map(&:text)
    assert_select ".buddy-link__input[value=?]", "www.example.com/b/orpheus"
    assert_select ".formula-bar__content", /=BUDDY\(you, \?\) → #N\/A/
  end

  test "copying your link from setup counts as sending it" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true, idea_skipped: true)
    get project_path
    assert_select ".project__step[data-state=current]", /Bring a buddy/
    assert_select ".buddy-card__title", "Build with a buddy"

    patch project_path, params: { project: { buddy_invited: true } }
    follow_redirect!
    assert_select ".buddy-card__title", "Invite sent"
    assert_select ".project__step", /Buddy invite sent/
  end

  test "paired, the sidebar card and the tab show the two of you" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], slack_joined: true)
    projects(:orpheus).pair_with(projects(:ana))
    get project_path

    assert_select ".buddy-card__title", "You + Ana"
    assert_select ".buddy-card__note", "Ana is building pong in Figma"
    assert_select ".project__step", /Paired with Ana/
  end
end
