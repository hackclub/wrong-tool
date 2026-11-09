require "test_helper"

class ShipSubmissionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:orpheus)
    @reviewer = users(:ana)
    @reviewer.update!(review_roles: %w[reviewer fraud])
    Airtable.stubbed = []
  end

  teardown { Airtable.stubbed = nil }

  test "an approved ship that passed the fraud check goes to the automation, with its hours and why" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) do
      FraudCheck.verdict(ship, by: @reviewer, score: 8, note: "Commits line up with the sessions.")
      decide(ship, "approved", approved_hours: "5", justification: checked, deflation_reason: "1h was on the menu screen")
    end

    assert ship.reload.approved?
    fields = Airtable.stubbed.last
    assert_equal 1, Airtable.stubbed.size
    assert_equal "wrong-tool-ship-#{ship.id}", fields["Submission Key"]
    assert fields["Automation - Submit to Unified YSWS"]
    assert_not fields["Rejected"]
    assert_equal 5.0, fields["Optional - Override Hours Spent"]
    assert_equal checked, fields["Justification - Specific Technical Features"]
    assert_equal "1h was on the menu screen", fields["Justification - Deflation Justification"]
    assert_equal "Fraud check: passed, trust 8/10. Commits line up with the sessions.", fields["Justification - Additional Justification"]
    assert_equal "orpheus", fields["GitHub Username"]
    assert_equal "https://github.com/orpheus/beat-sheet", fields["Code URL"]
    assert_match %r{\Ahttps://wrong\.hackclub\.com/rails/active_storage/}, fields["Screenshot"].first["url"]
    assert_equal ship.project.user.address["locality"], fields["City"]
    assert ship.airtable_record_id.present?
    assert ship.airtable_synced_at.present?
  end

  test "approved but still waiting on the fraud check isn't sent until it passes" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(ship, "approved", approved_hours: "6", justification: checked) }
    assert_empty Airtable.stubbed

    perform_enqueued_jobs(only: ShipSubmissionJob) { FraudCheck.verdict(ship, by: @reviewer, score: 6, note: "Mostly fine, one odd night.") }
    fields = Airtable.stubbed.last
    assert fields["Automation - Submit to Unified YSWS"]
    assert_match "passed (marked sus), trust 6/10", fields["Justification - Additional Justification"]
  end

  test "rejected in review: ticked Rejected with the note to the maker, never sent to the automation" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(ship, "rejected", note_to_maker: "This is a fork of someone else's game.") }

    fields = Airtable.stubbed.last
    assert fields["Rejected"]
    assert_not fields["Automation - Submit to Unified YSWS"]
    assert_equal "This is a fork of someone else's game.", fields["Rejection Reason"]
    assert_nil fields["Optional - Override Hours Spent"]
  end

  test "failing the fraud check: ticked Rejected with the score and note" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) { FraudCheck.verdict(ship, by: @reviewer, score: 2, note: "Hours are all one idle session.") }

    fields = Airtable.stubbed.last
    assert fields["Rejected"]
    assert_not fields["Automation - Submit to Unified YSWS"]
    assert_equal "Failed the fraud check (trust 2/10). Hours are all one idle session.", fields["Rejection Reason"]
  end

  test "a reship only counts the hours added since the project's last approved ship" do
    first = ship_now(hours: 4)
    first.update_columns(status: "approved", approved_hours: 4, decided_at: 1.day.ago)
    reship = ship_now(hours: 9)
    reship.update_columns(fraud_status: "good", fraud_score: 9)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(reship, "approved", approved_hours: "9", justification: checked) }

    fields = Airtable.stubbed.last
    assert_equal 5.0, fields["Optional - Override Hours Spent"]
    assert_match "this record counts only the 5 hrs added since", fields["Optional - Override Duplicate Justification"]
  end

  test "an admin changing the hours sends it again" do
    ship = ship_now(hours: 6)
    ship.update_columns(fraud_status: "good", fraud_score: 9)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(ship, "approved", approved_hours: "6", justification: checked) }
    admin = users(:orpheus)
    Rails.configuration.x.admin_slack_ids, admins = [ admin.slack_id ], Rails.configuration.x.admin_slack_ids
    perform_enqueued_jobs(only: ShipSubmissionJob) { ShipReview.change_hours(ship, by: admin, approved_hours: "3", justification: "Half was on another game.") }
    Rails.configuration.x.admin_slack_ids = admins

    assert_equal 2, Airtable.stubbed.size
    assert_equal 3.0, Airtable.stubbed.last["Optional - Override Hours Spent"]
    assert_match "An admin changed the hours since: Half was on another game.", Airtable.stubbed.last["Optional - Override Hours Spent Justification"]
  end

  test "the sweep sends decided ships Airtable hasn't got, and skips the ones in review" do
    decided = ship_now(hours: 3)
    decided.update_columns(status: "rejected")
    ship_now(hours: 2)

    ShipSubmissionJob.perform_now
    assert_equal [ "wrong-tool-ship-#{decided.id}" ], Airtable.stubbed.map { |fields| fields["Submission Key"] }

    ShipSubmissionJob.perform_now
    assert_equal 1, Airtable.stubbed.size, "nothing's changed since"
  end

  test "no token: nothing's sent" do
    Airtable.stubbed = nil
    key, Rails.configuration.x.airtable_api_key = Rails.configuration.x.airtable_api_key, nil
    ship = ship_now(hours: 3)
    ship.update_columns(status: "rejected")
    assert_nil ShipSubmission.sync!(ship)
  ensure
    Rails.configuration.x.airtable_api_key = key
  end

  private
    def decide(ship, decision, **attributes)
      ShipReview.decide(ship, by: @reviewer, decision:, **attributes)
    end

    def checked = "Played all three levels; the beat sync is in the formulas."

    def ship_now(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                             screenshot_shows_game: true)
    end
end
