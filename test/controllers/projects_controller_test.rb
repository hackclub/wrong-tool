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

  test "changing your tool, right on your project, keeps everything else" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    projects(:orpheus).pair_with(projects(:ana))
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(edit: "tool")
    assert_select ".project__tools button[aria-pressed=true]", text: projects(:orpheus).tool_name

    keep = projects(:orpheus).reload.attributes.slice("idea", "prize", "pace_minutes", "build_time", "signed_on")
    patch project_path, params: { project: { tool: "figma", tool_name: "Figma" } }
    assert_redirected_to project_path
    project = projects(:orpheus).reload
    assert_equal [ "figma", "Figma" ], [ project.tool, project.tool_name ]
    assert_equal keep, project.attributes.slice(*keep.keys)
    assert_equal [ "rhythm-game" ], project.hackatime_projects
    assert_equal projects(:ana), project.buddy

    patch project_path, params: { project: { tool: "other", tool_name: "Google Slides" } }
    assert_equal [ "other", "Google Slides" ], projects(:orpheus).reload.slice(:tool, :tool_name).values

    patch project_path, params: { project: { tool: "other", tool_name: " " } }
    assert_response :unprocessable_entity
    assert_select ".project__tools [role=alert]"
  end

  test "once you've pledged, going through onboarding again takes you to your project and keeps your pledge" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    assert_no_changes -> { projects(:orpheus).reload.attributes } do
      post project_path, as: :json, params: { project: { tool: "figma", tool_name: "Figma", idea: "a puzzle game", prize: "rg35xx",
                                                         pace_minutes: 60, build_time: "late night" } }
    end
    assert_response :ok
    assert_equal project_path, response.parsed_body["location"]
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
    assert_select ".project__meta", /done by Oct 19/
    assert_select ".app-bar__progress", "Day 1 of 14"
    assert_select ".project__step[data-state=current] .project__step-title", /Link Hackatime/
    assert_select ".project__step[data-state=locked]", /Link your Hackatime project/
    assert_select ".project__setup-count", "1 required step left"
    assert_select ".formula-bar__content", /#REF!/
    assert_select ".project__streak", count: 0
  end

  test "setup walks you through every step after Hackatime, one at a time, and Clippy congratulates you at the end" do
    with_hackatime_hours(1.5) do
      sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
      mock_hackatime
      post "/auth/hackatime"
      follow_redirect!
      assert_equal "hop", flash[:clippy]
      assert projects(:orpheus).set_up?, "linking Hackatime is all setup needs to unlock things"

      get project_path
      assert_select ".project__setup-count", "3 optional steps left"
      assert_select ".project__step[data-state=current] .project__step-title", /Link your Hackatime project/
      assert_no_match(/#wrong\b/, css_select(".project__steps").text, "everyone's added to #wrong for them")

      patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game" ] } }
      follow_redirect!
      assert_select ".project__step[data-state=current] .project__step-title", /Add your git repo/
      assert_select ".project__say", "Hours count now. A couple of quick things and you're in."
      assert_select ".project__schedule", count: 0

      patch project_path, params: { project: { repo_later: true } }
      follow_redirect!
      assert_select ".project__step[data-state=current] .project__step-title", /Bring a buddy/

      patch project_path, params: { project: { buddy_skipped: true } }
      assert_equal "congratulate", flash[:clippy]
      follow_redirect!
      assert_select ".project__say", "1 day in a row. 20 min today keeps it going.", "the 1.5 hours yesterday count"
      assert_select ".formula-bar__content", /TRUE/
      assert_select ".project__setup-summary", "Setup done"
      assert_equal [ "1.5 of 10 hrs", "45 min", "Oct 19" ], css_select(".project__goal-value").map(&:text)
      assert_equal [ "5 hrs · shoutout", "10 hrs · handheld", "20 hrs · +$85" ], css_select(".project__track-label").map(&:text)
      assert_select ".project__day-cell[data-state=party]", /Party/
      assert_select ".project__event[data-kind=party]", /Play party.*Thursday at 7pm · on stream/m
      assert_select ".project__event[data-kind=ship] .project__event-day", "20", "the deadline, not the day your hours would be in"
      assert_select ".project__event[data-kind=ship] .project__event-title", "Deadline"
      assert_select ".project__schedule-note", "14 sessions of 45 min gets you there by Oct 19. Ship any time up to Oct 20."
      assert_select ".project__day-cell[data-state=goal]", /Goal/
      assert_select ".project__day-cell[data-state=due] .project__day-date", "20"
      assert_select ".project__day-cell[data-state=hit] .project__day-value", "1.5h", "yesterday's 1.5 hours fill its cell"
      assert_select ".project__stair[data-you]", /You/
      assert_select ".project__stairs-note", "Hours this week. You're in first."
      assert_equal [ "Gold star for Clippy", "Flame on the leaderboard", "1 skip day", "Shoutout in #wrong" ],
                   css_select(".project__reward-label").map(&:text)
    end
  end

  test "adding your game to the play party queue" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    patch project_path, params: { project: { party_queued: true } }
    follow_redirect!

    assert_select ".project__party-queued", /In the queue/
    assert_select ".project__event[data-kind=party]", /We'll play your game live/
  end

  test "the Hackatime projects dropdown lists your Hackatime projects to tick, and only those can be linked" do
    link_hackatime(users(:orpheus))
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_select ".project__step-text", /Only time from Oct 6 on counts/
    assert_equal [ "rhythm-game", "beat-sheet-art", "dotfiles" ], css_select(".project__picker-name").map(&:text)
    assert_equal [ "1.5 hrs", "0.3 hrs", "3.1 hrs" ], css_select(".project__picker-note").map(&:text)
    assert_select ".project__picker-box[checked]", count: 0
    assert_select "button[disabled]", "Tick a project above"

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game", "dotfiles" ] } }
    follow_redirect!
    assert_equal [ "rhythm-game", "dotfiles" ], projects(:orpheus).reload.hackatime_projects

    get project_path(step: "hackatime_project")
    assert_equal %w[rhythm-game dotfiles], css_select(".project__picker-box[checked]").map { |box| box["value"] }
    assert_select ".project__picker-value", "rhythm-game, dotfiles"
    assert_select "button", "Link 2 projects"

    patch project_path, params: { project: { hackatime_project_names: [ "" ] } }
    assert_response :unprocessable_entity
    assert_select ".project__step-error", /need one picked/

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game", "someone-elses-game" ] } }
    assert_response :unprocessable_entity
    assert_select ".project__step[data-state=current] .project__step-error", /don't include someone-elses-game on Hackatime/
    assert_equal [ "rhythm-game", "dotfiles" ], projects(:orpheus).reload.hackatime_projects
  end

  test "with only Hackatime's catch-all Other to pick, the step says what Other is and how to get a project of your own" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_baseline: %w[Other rhythm-game beat-sheet-art dotfiles])
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_only_hackatime_projects(Hackatime::Project.new("Other", 600)) { get project_path }
    assert_equal [ "Other" ], css_select(".project__picker-name").map(&:text)
    assert_select ".project__step-waiting", /"Other" is Hackatime's name for time with no project name/
    assert_select ".project__step-waiting", /Record a session of building with Lapse/
    assert_select "button[disabled]", "Tick a project above"

    with_hackatime_projects(Hackatime::Project.new("Other", 600)) { get project_path }
    assert_select ".project__step-waiting", count: 0
  end

  test "the first new Hackatime project you log time on links itself, until you keep it or change it" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    mock_hackatime
    post "/auth/hackatime"
    follow_redirect!
    assert_equal %w[rhythm-game beat-sheet-art dotfiles], projects(:orpheus).reload.hackatime_baseline

    get project_path
    assert_empty projects(:orpheus).reload.hackatime_projects, "projects you already had don't link themselves"
    assert_select ".project__auto-linked", count: 0
    assert_select ".project__step-hint", /The first new project you log time on links itself/

    with_hackatime_projects(Hackatime::Project.new("wrong-tool-game", 120), Hackatime::Project.new("scratch", 0)) do
      get project_path
    end
    project = projects(:orpheus).reload
    assert_equal [ "wrong-tool-game" ], project.hackatime_projects
    assert project.hackatime_auto_linked?
    assert project.step_done?("hackatime_project")
    assert_select ".project__auto-linked-title", "New time on Hackatime for wrong-tool-game"
    assert_select ".project__auto-linked a[href=?]", project_path(step: "hackatime_project"), "Change"
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/new time from you on \*wrong-tool-game\*, so it's linked to \*A rhythm game in Spreadsheet\*/, dm[:args].second)

    patch project_path, params: { project: { hackatime_auto_linked: false } }
    assert_redirected_to project_path
    assert_not projects(:orpheus).reload.hackatime_auto_linked?
    assert_equal [ "wrong-tool-game" ], projects(:orpheus).hackatime_projects
  end

  test "picking your Hackatime projects yourself replaces one that linked itself, and nothing links itself after" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_baseline: [ "rhythm-game", "beat-sheet-art" ], hackatime_projects: [ "dotfiles" ],
                               hackatime_auto_linked: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game" ] } }
    project = projects(:orpheus).reload
    assert_equal [ "rhythm-game" ], project.hackatime_projects
    assert_not project.hackatime_auto_linked?

    with_hackatime_projects(Hackatime::Project.new("wrong-tool-game", 120)) { get project_path }
    assert_equal [ "rhythm-game" ], projects(:orpheus).reload.hackatime_projects
    assert_select ".project__auto-linked", count: 0
  end

  test "with nothing on Hackatime to pick yet, setup goes on without it, and your first project links itself later" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_baseline: [])
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_only_hackatime_projects do
      get project_path
      assert_select ".project__step[data-state=current] .project__step-title", /Add your git repo/
      assert_select ".project__step[data-state=pending] .project__step-title", /Record your first session with Lapse/
      assert_select ".project__step[data-state=pending] .project__step-note", /it links itself/
      assert_select ".project__step[data-state=pending] .project__step-waiting", /Record a session of building with Lapse/
      assert_select ".project__step[data-state=pending] a[href=?]", "https://lapse.hackclub.com/", "Get Lapse"
      assert_select ".project__setup-count", "2 optional steps left"
      assert_select ".project__say", "Hackatime's linked. Record with Lapse and your project links itself."

      patch project_path, params: { project: { repo_later: true } }
      patch project_path, params: { project: { buddy_skipped: true } }
      assert_equal "congratulate", flash[:clippy]
      follow_redirect!
      assert_select ".project__setup-summary", "Setup done"
      assert_select ".formula-bar__content", /#N\/A/
      assert_select ".project__linked-none", /Record with Lapse and your project links itself/
      assert_select ".project__linked a", "Pick"
      assert_select ".project__say", "All set. Record with Lapse and your project links itself."
      assert_select ".project__ship", count: 0
      get project_ship_path
      assert_redirected_to project_path, "nothing to ship hours from yet"

      get project_path(step: "hackatime_project")
      assert_select ".project__step-waiting", /Record a session of building with Lapse/
      assert_select ".project__step-hint", /Nothing on Hackatime since .* yet/
      assert_select ".project__step-error", count: 0

      get hours_project_path(refresh: 1)
      assert_not response.parsed_body["tracking"]
    end

    with_only_hackatime_projects(Hackatime::Project.new("wrong-tool-game", 120)) do
      get hours_project_path(refresh: 1)
      assert response.parsed_body["tracking"], "the page's watcher learns it linked itself"
      assert_equal "hop", flash[:clippy]
    end
    assert_equal [ "wrong-tool-game" ], projects(:orpheus).reload.hackatime_projects
  end

  test "with Hackatime projects to pick, setup isn't through until you pick yours" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_select ".project__step[data-state=current] .project__step-title", /Link your Hackatime project/
    assert_select ".project__picker"
    assert_select ".project__schedule", count: 0
    assert_select ".project__say", "Hackatime's linked. Which project is yours?"

    patch project_path, params: { project: { hackatime_project_names: [ "rhythm-game" ] } }
    assert_equal "congratulate", flash[:clippy]
  end

  test "when Hackatime stops accepting your token, you're asked to link it again" do
    users(:orpheus).update!(hackatime_uid: "9999", hackatime_access_token: "revoked")
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path

    assert_select ".project__step-error", /Your Hackatime link expired/
    assert_select "form[action='/auth/hackatime'] button", "Link Hackatime again"
    assert_select ".project__picker", count: 0
  end

  test "your hours come from your linked Hackatime projects, and the pomodoro can ask for them" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game", "dotfiles" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    with_hackatime_hours(4.6) { get hours_project_path(refresh: 1) }
    assert_response :success
    assert_equal [ 4.6, "4.6 of 10 hrs", true ], response.parsed_body.values_at("hours", "label", "tracking")

    get project_path
    assert_select ".project__goal-value", "4.6 of 10 hrs", "what the refresh synced, without asking Hackatime again"
    assert_select ".project__stair[data-you] .project__stair-hours", "4.6h", "the leaderboard counts the same hours"
    assert_select ".project__length input[checked]" do |inputs|
      assert_equal "25", inputs.first["value"]
    end
    assert_select ".project__start", /Start pomodoro/
  end

  test "a step you can still do opens when you pick it" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(step: "repo")
    assert_select ".project__step[data-state=current]", /Add your git repo/

    get project_path(step: "hackatime_project")
    assert_select ".project__step[data-state=current]", /Link Hackatime/, "it's locked until Hackatime is linked"
  end

  test "once you're set up, you can change your daily pace" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get project_path(edit: "pace")
    assert_select ".project__pace[aria-pressed=true]", "45 min"

    patch project_path, params: { project: { pace_minutes: 120 } }
    follow_redirect!
    assert_select ".project__goal-value", "2 hrs"
  end

  test "renaming your project and adding a screenshot" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
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
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
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

    # As if these were all Orpheus had logged time on on Hackatime.
    def with_only_hackatime_projects(*projects)
      before = Hackatime.stubbed_projects
      Hackatime.stubbed_projects = before.merge("1001" => projects)
      yield
    ensure
      Hackatime.stubbed_projects = before
    end

    # As if Orpheus had logged time on these on Hackatime too.
    def with_hackatime_projects(*added)
      before = Hackatime.stubbed_projects
      Hackatime.stubbed_projects = before.merge("1001" => before.fetch("1001") + added)
      yield
    ensure
      Hackatime.stubbed_projects = before
    end
end
