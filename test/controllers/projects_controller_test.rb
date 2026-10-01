require "test_helper"

class ProjectsControllerTest < ActionDispatch::IntegrationTest
  test "without a project, it's back to onboarding" do
    get project_path
    assert_redirected_to onboarding_path

    sign_in_as(mock_hack_club_auth)
    get project_path
    assert_redirected_to onboarding_path
  end

  test "signing the pledge makes your project" do
    sign_in_as(mock_hack_club_auth)

    post project_path, as: :json, params: { project: { tool: "figma", tool_name: "Figma", idea: "something cursed",
                                                       prize: "rg35xx", pace_minutes: 60, build_time: "late night" } }

    assert_response :created
    assert_equal project_path, response.parsed_body["location"]
    project = User.find_by!(hca_id: "ident!heidi").project
    assert_equal [ "Something cursed in Figma", 60, Date.current ], [ project.title, project.pace_minutes, project.signed_on ]
  end

  test "a pledge needs someone signed in, and answers onboarding offers" do
    post project_path, as: :json, params: { project: { tool: "figma" } }
    assert_response :unauthorized

    sign_in_as(mock_hack_club_auth)
    post project_path, as: :json, params: { project: { tool: "notepad", tool_name: "Notepad", idea: "a game", prize: "miyoo",
                                                       pace_minutes: 45, build_time: "evening" } }
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["errors"], "Tool is not included in the list"
  end

  test "your project shows your pledge and what's left to set up" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_response :success
    assert_select "h1 .project__title", "A rhythm game in Spreadsheet"
    assert_select ".project__meta", /done by Oct 15/
    assert_select ".app-bar__progress", "Day 1 of 14"
    assert_select ".project__step[data-state=current] .project__step-title", /Link Hackatime/
    assert_select ".project__step[data-state=locked]", /Link your Hackatime project/
    assert_select ".project__setup-count", "0 of 3 required"
    assert_select ".formula-bar__content", /#REF!/
    assert_select ".project__streak", count: 0
  end

  test "ticking off the last required setup step has Clippy congratulate you" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { tracker: "hackatime" } }
    assert_equal "hop", flash[:clippy]
    patch project_path, params: { project: { link_hackatime_project: "rhythm-game" } }
    patch project_path, params: { project: { slack_joined: true } }

    assert_redirected_to project_path
    assert_equal "congratulate", flash[:clippy]
    follow_redirect!
    assert_select ".project__say", "All set. 20 min today starts your streak."
    assert_select ".formula-bar__content", /TRUE/
    assert_select ".project__setup-summary", /Setup done · 2 optional steps left/
    assert_equal [ "0 of 10 hrs", "45 min", "Oct 15" ], css_select(".project__goal-value").map(&:text)
    assert_equal [ "5 hrs · shoutout", "10 hrs · handheld", "20 hrs · +$85" ], css_select(".project__track-label").map(&:text)
    assert_select ".project__day-cell[data-state=party]", /Party/
    assert_select ".project__event[data-kind=party]", /Play party.*Thursday at 7pm · on stream/m
    assert_select ".project__event[data-kind=ship] .project__event-day", "15"
    assert_select ".project__stair[data-you]", /You/
    assert_select ".project__stairs-note", "Hours this week. You're on top."
    assert_equal [ "Gold star for Clippy", "+1 skip day", "Sticker pack with your Miyoo" ],
                 css_select(".project__reward-label").map(&:text)
  end

  test "adding your game to the play party queue" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { party_queued: true } }
    follow_redirect!

    assert_select ".project__party-queued", /In the queue/
    assert_select ".project__event[data-kind=party]", /We'll play your game live/
  end

  test "the Hackatime project dropdown lists your Hackatime projects, and only those can be linked" do
    projects(:orpheus).update!(tracker: "hackatime")
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_equal [ "Pick a project", "rhythm-game · 1.5 hrs", "beat-sheet-art · 0.3 hrs", "dotfiles · 3.1 hrs" ],
                 css_select("select#project_link_hackatime_project option").map(&:text)

    patch project_path, params: { project: { link_hackatime_project: "someone-elses-game" } }
    assert_response :unprocessable_entity
    assert_select ".project__step[data-state=current] .project__step-error", /don't include someone-elses-game on Hackatime/
    assert_empty projects(:orpheus).reload.hackatime_projects
  end

  test "someone Hackatime doesn't know is told how to fix it" do
    users(:orpheus).update!(slack_id: "U0NOBODY")
    projects(:orpheus).update!(tracker: "hackatime")
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0NOBODY"))
    get project_path

    assert_select ".project__step-error", /Hackatime doesn't know you yet/
    assert_select "select#project_link_hackatime_project", count: 0
  end

  test "a step you can still do opens when you pick it" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(step: "slack")
    assert_select ".project__step[data-state=current]", /Join #wrong-tool on Slack/

    get project_path(step: "hackatime_project")
    assert_select ".project__step[data-state=current]", /Link Hackatime/, "it's locked until Hackatime is linked"
  end

  test "once you're set up, you can change your daily pace" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true,
                               idea_posted: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(edit: "pace")
    assert_select ".project__pace[aria-pressed=true]", "45 min"

    patch project_path, params: { project: { pace_minutes: 120 } }
    follow_redirect!
    assert_select ".project__goal-value", "2 hrs"
  end

  test "renaming your project and adding a screenshot" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true,
                               idea_posted: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { name: "Beat Sheet" } }
    patch project_path, params: { project: { screenshot: fixture_file_upload("screenshot.png", "image/png") } }
    follow_redirect!

    assert_select ".project__title", "Beat Sheet"
    assert_select ".project__shot-image[alt='Screenshot of Beat Sheet']"
    get leaderboard_path
    assert_select "tr[data-you] .leaderboard__shot"
  end

  test "a screenshot that isn't an image says so" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true,
                               idea_posted: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { screenshot: fixture_file_upload("notes.txt", "text/plain") } }

    assert_response :unprocessable_entity
    assert_select ".project__shot-error", /should be a PNG/
    assert_select ".project__shot-placeholder", "Add a screenshot"
  end

  test "a repo that isn't a link says so" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { repo_url: "my game" } }

    assert_response :unprocessable_entity
    assert_select ".project__step[data-state=current] .project__step-error", /should be a link/
  end

  private
    def sign_in_as(_auth)
      post "/auth/hackclub"
      follow_redirect!
    end
end
