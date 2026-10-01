require "application_system_test_case"

class ProjectTest < ApplicationSystemTestCase
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    visit onboarding_path
  end

  test "setting up: link Hackatime and your project, join Slack, then put off the repo and post your idea" do
    sign_in_and_open_project

    assert_selector ".project__say", text: "Nothing's linked yet, so your hours won't count."
    assert_selector ".app-bar__avatar", text: "O"
    assert_text "Streaks and the leaderboard open once you're set up."
    click_on "Link Hackatime"

    assert_selector ".project__say", text: "Hackatime's linked. Which project is yours?"
    assert_selector ".project__step[data-state=done]", text: "Hackatime linked"
    select "rhythm-game · 1.5 hrs", from: "Hackatime project"
    click_on "Link project"

    assert_selector ".project__step[data-state=done]", text: "Linked to rhythm-game"
    click_on "Join #wrong-tool"

    assert_selector ".formula-bar__content", text: "→ TRUE"
    assert_selector ".project__say", text: "All set. 20 min today starts your streak."
    assert_selector ".project__streak-number", text: "0"
    find(".project__setup-summary", text: "Setup done · 2 optional steps left").click
    click_on "Later"
    find(".project__setup-summary", text: "Setup done · 1 optional step left").click
    click_on "Post"
    assert_selector ".project__setup-summary", exact_text: "Setup done"

    click_on "Add to queue"
    assert_selector ".project__party-queued", text: "In the queue"
  end

  test "renaming your project in place, and adding a screenshot" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true,
                               idea_posted: true)
    sign_in_and_open_project

    click_on "Rename"
    fill_in "Project name", with: "Beat Sheet\n"
    assert_selector ".project__title-button", text: "Beat Sheet"
    assert_selector ".app-bar__title--file", text: "beat_sheet"

    click_on "Rename"
    fill_in "Project name", with: "Something else"
    find_field("Project name").send_keys(:escape)
    assert_selector ".project__title-button", text: "Beat Sheet"

    find(".project__shot-slot input[type=file]", visible: :all).attach_file(file_fixture("screenshot.png"), make_visible: true)
    assert_selector ".project__shot-image[alt='Screenshot of Beat Sheet']"
  end

  test "seeing which Hackatime projects are linked, and changing them" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true,
                               idea_posted: true)
    sign_in_and_open_project
    assert_selector ".project__linked-project", text: "rhythm-game"

    within(".project__linked") { click_on "Change" }
    assert_no_selector "option", text: "rhythm-game", visible: :all # already linked
    select "beat-sheet-art · 0.3 hrs", from: "Hackatime project"
    click_on "Add"

    assert_selector ".project__linked .project__linked-project", count: 2
    assert_equal [ "rhythm-game", "beat-sheet-art" ], all(".project__linked .project__linked-project").map(&:text)

    within(".project__linked") { click_on "Change" }
    find("button[aria-label='Unlink rhythm-game']").click
    assert_selector ".project__linked .project__linked-project", count: 1
    assert_selector ".project__linked", text: "beat-sheet-art"
  end

  test "the leaderboard ranks everyone set up, and you" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true, repo_later: true,
                               idea_posted: true)
    sign_in_and_open_project
    click_on "See all"

    assert_current_path leaderboard_path
    assert_selector "h1", text: "Leaderboard"
    assert_selector "tr[data-you]", text: "You"
    assert_text "Most hours built this week."
    click_on "Streak"
    assert_text "Longest streaks right now."

    click_on "Hall of Wrong"
    assert_current_path hall_path
    assert_selector "tr[data-you]", text: "You're building here"
  end

  test "shipping: the form says what it still needs, then it's in review" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true)
    sign_in_and_open_project
    find(".project__ship").click

    assert_selector ".ship__heading", text: "Ship your project"
    assert_button "Ship it", disabled: true
    assert_selector ".ship__missing", text: "Still needs a description (40+ characters), a repo URL, a demo URL, a screenshot, a screenshot check."

    fill_in "Title", with: "Beat Sheet"
    assert_selector ".ship__hall-title", text: "Beat Sheet"
    fill_in "Description", with: "A rhythm game where every beat is a cell lighting up in time."
    assert_selector ".ship__count[data-enough]"
    fill_in "Repo URL", with: "github.com/orpheus/beat-sheet"
    fill_in "Demo URL", with: "https://example.com/beat"
    find(".ship__shot input[type=file]", visible: :all).attach_file(file_fixture("screenshot.png"), make_visible: true)
    check "It shows the game running inside Spreadsheet, not a mockup."

    assert_selector ".ship__missing", text: "Ready to ship."
    click_on "Ship it"
    assert_selector ".ship__done-title", text: "Shipped."
    click_on "Back to project"
    assert_selector ".project__title", text: "Beat Sheet"
    assert_selector ".project__ship", text: "In review"
  end

  test "a focus session: a round of your pace, pause, end it, then back to the project" do
    projects(:orpheus).update!(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ], slack_joined: true)
    sign_in_and_open_project
    click_on "Start session"

    assert_selector ".focus__label", text: "FOCUS · ROUND 1"
    assert_selector ".focus__clock", text: /\A(45:00|44:5\d)\z/
    assert_selector ".focus__title", text: "A rhythm game in Spreadsheet"
    assert_selector ".focus__track-name", text: "#REF! in the rain"
    click_on "Pause"
    assert_selector ".focus__label", text: "PAUSED · ROUND 1"
    click_on "Resume"
    click_on "End session"

    assert_selector ".focus__label", text: "SESSION DONE"
    assert_selector ".focus__title", text: "Short one. Every minute counts."
    click_on "Take a 5 min break"
    assert_selector ".focus__label", text: "BREAK"
    assert_selector ".focus__clock", text: /\A(05:00|04:5\d)\z/
    click_on "Skip break"
    assert_selector ".focus__label", text: "FOCUS · ROUND 2"
    find("button[aria-label='Next track']").click
    assert_selector ".focus__track-name", text: "Merge conflict lullaby"

    click_on "Exit focus"
    assert_no_selector ".focus"
    assert_selector ".project__title", text: "A rhythm game in Spreadsheet"
  end

  test "the avatar opens your account, where you can log out" do
    sign_in_and_open_project
    find(".app-bar__avatar", text: "O").click
    click_on "Log out"

    assert_current_path root_path
    assert_selector ".app-bar__build-button"
  end

  test "once you're done with onboarding, its tab goes" do
    sign_in_and_open_project
    assert_no_selector ".sheet-tab", text: "Onboarding"
    assert_equal [ "My project", "Leaderboard", "Hall of Wrong" ], all(".sheet-tab").map(&:text)

    visit onboarding_path
    assert_selector ".sheet-tab[aria-current=page]", text: "Onboarding"
    assert_selector ".onboarding__project-tab[aria-disabled=false]"
  end

  private
    # Signs in with Hack Club Auth (as Orpheus, whose project is in the fixtures) and opens the project.
    def sign_in_and_open_project
      execute_script(<<~JS)
        const form = document.createElement("form")
        form.method = "post"
        form.action = "/auth/hackclub"
        document.body.append(form)
        form.submit()
      JS
      assert_current_path onboarding_path
      visit project_path
      assert_selector "h1", text: "A rhythm game in Spreadsheet"
      execute_script("window.open = () => null") # the steps' own tabs aren't under test here
    end
end
