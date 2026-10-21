require "test_helper"

class ExtensionNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0KARTIKEY" ]
    @extension = projects(:ana).create_extension!(reason: "exams until the 22nd")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "asking DMs each admin why, with a button to decide" do
    ExtensionNotifier.requested(@extension)

    dms = enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
    assert_equal [ "U0ORPHEUS", "U0KARTIKEY" ], dms.map { |job| job[:args].first }
    assert_equal "Ana Lovelace asked for 7 more days on *Pong in Figma*, built in Figma:\n>exams until the 22nd", dms.first[:args].second
    assert_equal [ "Decide on wrong tool", "https://wrong.hackclub.com/admin/extensions" ], dms.first[:args].third["link"]
  end

  test "a decision is a DM from Clippy, with the deadline it leaves them" do
    @extension.decide!("approved", by: users(:orpheus))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_equal "7 more days. *Pong in Figma* is due Oct 27 now. Ship it whenever it's playable.\n" \
                 ":clippy-excited: clippy is doing a little dance. :dino-bbq:", dm[:args].second
    assert_equal [ "Open wrong tool", "https://wrong.hackclub.com/project" ], dm[:args].third["link"]
    assert_not_nil users(:ana).reload.slack_dmed_at

    clear_enqueued_jobs
    denied = projects(:orpheus).create_extension!(reason: "busy")
    denied.decide!("denied", by: users(:ana))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/No extra days this time, so \*A rhythm game in Spreadsheet\* is still due Oct 27/, dm[:args].second)
  end

  test "nothing to someone who stopped Clippy's messages, or isn't on Slack" do
    users(:ana).update!(slack_muted_at: Time.current)
    @extension.decide!("approved", by: users(:orpheus))
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }

    users(:orpheus).update!(slack_id: nil)
    projects(:orpheus).create_extension!(reason: "busy").decide!("denied", by: users(:ana))
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
  end
end
