require "test_helper"

class ExtensionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0KARTIKEY" ]
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "asking for more time, once, with why" do
    sign_in_as_orpheus
    get project_path
    assert_select ".project__days-extension a.project__event-button", "Need more time?"
    assert_select ".project__event[data-kind=ship] .project__event-button", 0, "not in the events card"
    assert_select ".project__extension-form", 0

    get project_path(edit: "extension")
    assert_select ".project__days-extension .project__extension-form[action=?]", project_extension_path
    assert_select ".project__extension-form button", "Ask for 7 more days"

    post project_extension_path, params: { extension: { reason: " exams until the 22nd " } }
    assert_redirected_to project_path
    assert_equal "hop", flash[:clippy]
    extension = projects(:orpheus).reload.extension
    assert extension.pending?
    assert_equal "exams until the 22nd", extension.reason
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0KARTIKEY" }
    assert_match(/asked for 7 more days on \*A rhythm game in Spreadsheet\*.*\n>exams until the 22nd/, dm[:args].second)

    follow_redirect!
    assert_select ".project__days-extension .project__extension[data-state=pending]", "Asked for 7 more days. You'll hear from Clippy."
    assert_select ".project__days-extension .project__event-button", 0
    assert_select ".project__event[data-kind=ship] .project__event-day", "20", "asking alone moves nothing"

    assert_no_difference -> { Extension.count } do
      post project_extension_path, params: { extension: { reason: "and more" } }
    end
    assert_redirected_to project_path
  end

  test "it needs a reason" do
    sign_in_as_orpheus
    assert_no_difference -> { Extension.count } do
      post project_extension_path, params: { extension: { reason: "  " } }
    end
    assert_redirected_to project_path(edit: "extension")
    follow_redirect!
    assert_select ".project__extension-form .project__step-error[role=alert]", "Reason is needed: a line on why"
    assert_select ".project__extension-reason[aria-invalid=true]"
  end

  test "not once you've shipped, or past the deadline where you are" do
    sign_in_as_orpheus
    projects(:orpheus).ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, built in Sheets.",
                                     repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", status: "approved",
                                     screenshot: fixture_file_upload("screenshot.png", "image/png"), screenshot_shows_game: true)
    assert_no_difference -> { Extension.count } do
      post project_extension_path, params: { extension: { reason: "exams" } }
    end
    assert_redirected_to project_path
    projects(:orpheus).ships.destroy_all

    travel_to Time.utc(2026, 10, 21, 12) do # UTC until they've said where they are
      get project_path
      assert_select ".project__days-extension .project__event-button", 0
      assert_no_difference -> { Extension.count } do
        post project_extension_path, params: { extension: { reason: "exams" } }
      end
      assert_redirected_to project_path
    end
  end

  test "how it went, on the card" do
    sign_in_as_orpheus
    extension = projects(:orpheus).create_extension!(reason: "exams")

    extension.update!(status: "approved")
    get project_path
    assert_select ".project__extension[data-state=approved]", "Extended by 7 days."
    assert_select ".project__event[data-kind=ship] .project__event-day", "27"
    assert_select ".project__schedule-note", /Ship any time up to Oct 27\./
    assert_select ".project__day-cell[data-state=due] .project__day-date", "27"

    extension.update!(status: "denied")
    get project_path
    assert_select ".project__extension[data-state=denied]", /No extra days this time/
    assert_select ".project__event[data-kind=ship] .project__event-day", "20"
  end

  private
    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
