require "test_helper"

class ShipSubmissionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:orpheus)
    @reviewer = users(:ana)
    @reviewer.update!(review_roles: %w[reviewer fraud])
    @project.user.update!(birthdate: "2010-04-01")
    Airtable.stubbed = Airtable::Stub.new
  end

  teardown { Airtable.stubbed = nil }

  test "an approved ship that passed the fraud check goes to the automation, with its hours and why" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) do
      FraudCheck.verdict(ship, by: @reviewer, score: 8, note: "Commits line up with the sessions.")
      decide(ship, "approved", approved_hours: "5", justification: checked, deflation_reason: "1h was on the menu screen")
    end

    assert ship.reload.approved?
    fields = sent
    assert_equal 1, Airtable.stubbed.upserts
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
    assert ship.airtable_submitted_at.present?
  end

  test "approved but still waiting on the fraud check isn't sent until it passes" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(ship, "approved", approved_hours: "6", justification: checked) }
    assert_empty Airtable.stubbed.records

    perform_enqueued_jobs(only: ShipSubmissionJob) { FraudCheck.verdict(ship, by: @reviewer, score: 6, note: "Mostly fine, one odd night.") }
    fields = sent
    assert fields["Automation - Submit to Unified YSWS"]
    assert_match "passed (marked sus), trust 6/10", fields["Justification - Additional Justification"]
  end

  test "rejected in review: ticked Rejected with the note to the maker, never sent to the automation" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(ship, "rejected", note_to_maker: "This is a fork of someone else's game.") }

    fields = sent
    assert fields["Rejected"]
    assert_not fields["Automation - Submit to Unified YSWS"]
    assert_equal "This is a fork of someone else's game.", fields["Rejection Reason"]
    assert_nil fields["Optional - Override Hours Spent"]
  end

  test "failing the fraud check: ticked Rejected with the score and note" do
    ship = ship_now(hours: 6)
    perform_enqueued_jobs(only: ShipSubmissionJob) { FraudCheck.verdict(ship, by: @reviewer, score: 2, note: "Hours are all one idle session.") }

    fields = sent
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

    fields = sent
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

    assert_equal 2, Airtable.stubbed.upserts
    assert_equal 3.0, sent["Optional - Override Hours Spent"]
    assert_match "An admin changed the hours since: Half was on another game.", sent["Optional - Override Hours Spent Justification"]
  end

  test "the sweep sends decided ships Airtable hasn't got, and skips the ones in review" do
    decided = ship_now(hours: 3)
    decided.update_columns(status: "rejected")
    ship_now(hours: 2)

    ShipSubmissionJob.perform_now
    assert_equal [ "wrong-tool-ship-#{decided.id}" ], sent_keys

    ShipSubmissionJob.perform_now
    assert_equal 1, Airtable.stubbed.upserts, "nothing's changed since"
  end

  test "approved without an address or birthday: on Airtable, but not ticked for Unified YSWS until the record has them" do
    @project.user.update!(address: nil, birthdate: nil)
    ship = ship_now(hours: 6)
    ship.update_columns(fraud_status: "good", fraud_score: 9)
    perform_enqueued_jobs(only: ShipSubmissionJob) { decide(ship, "approved", approved_hours: "6", justification: checked) }

    assert_equal 6.0, sent["Optional - Override Hours Spent"]
    assert_not sent[ShipSubmission::SUBMIT], "no address or birthday yet"
    assert_nil ship.reload.airtable_submitted_at

    # Someone fills in the address on Airtable, but not the birthday: still not.
    record_id = ship.airtable_record_id
    Airtable.stubbed.records[record_id].merge!("Address (Line 1)" => "15 Falls Rd", "City" => "Shelburne", "ZIP / Postal Code" => "05482",
                                               "Country" => "US")
    ShipSubmissionJob.perform_now
    assert_not sent[ShipSubmission::SUBMIT]

    # And the birthday: the sweep looks again and ticks it, keeping what was filled in.
    Airtable.stubbed.records[record_id]["Birthday"] = "2010-04-01"
    ShipSubmissionJob.perform_now
    assert sent[ShipSubmission::SUBMIT]
    assert_equal "Shelburne", sent["City"]
    assert ship.reload.airtable_submitted_at.present?

    ShipSubmissionJob.perform_now
    assert_equal 3, Airtable.stubbed.upserts, "ticked, so the sweep leaves it be"
  end

  test "a blank address line doesn't count" do
    assert_not ShipSubmission.complete?("Address (Line 1)" => " ", "City" => "Shelburne", "ZIP / Postal Code" => "05482", "Country" => "US",
                                        "Birthday" => "2010-04-01")
  end

  test "no address or birthday on us: those fields are left out, so what's on Airtable stays" do
    @project.user.update!(address: nil, birthdate: nil)
    ship = ship_now(hours: 3)
    ship.update_columns(status: "rejected")
    ShipSubmission.sync!(ship)

    fields = sent
    %w[Address\ (Line\ 1) City State\ /\ Province ZIP\ /\ Postal\ Code Country Birthday].each { |field| assert_not fields.key?(field), field }
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
    # The record as Airtable has it, for the one ship sent last.
    def sent = Airtable.stubbed.records.values.last

    def sent_keys = Airtable.stubbed.records.values.map { |fields| fields["Submission Key"] }

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
