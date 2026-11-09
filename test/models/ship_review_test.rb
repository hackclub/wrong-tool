require "test_helper"

class ShipReviewTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:orpheus)
    @reviewer = users(:ana)
    @reviewer.update!(review_roles: [ "reviewer" ])
  end

  test "approving grants the hours it took, or fewer with why, and needs what was checked" do
    ship = ship_now(hours: 6)

    decision = decide(ship, "approved", approved_hours: "6", justification: "too short")
    assert_not decision.persisted?
    assert_includes decision.errors.full_messages, "Justification needs at least 30 characters: what you checked, and what's in it"

    decision = decide(ship, "approved", approved_hours: "99", justification: checked)
    assert_includes decision.errors.full_messages, "Approved hours can't be more than the 6.0 it took"

    decision = decide(ship, "approved", approved_hours: "4", justification: checked)
    assert_includes decision.errors.full_messages, "Deflation reason needs at least 10 characters: why some hours don't count"
    assert ship.reload.in_review?, "nothing's decided until it's all there"
    assert_empty ship.review_decisions

    decision = decide(ship, "approved", approved_hours: "4", justification: checked, deflation_reason: "2h were on another game",
                                        note_to_maker: "Lovely little game.")
    assert decision.persisted?
    assert ship.reload.approved?
    assert_equal [ 4, @reviewer ], [ ship.approved_hours, ship.decided_by ]
    assert_equal 4, @project.reload.hours_approved
    assert_equal [ decision ], ship.review_decisions.to_a
    assert_equal decision, ship.verdict

    assert_not decide(ship, "rejected", note_to_maker: "Changed my mind about it.").persisted?, "decided already"
    assert ship.reload.approved?
  end

  test "an admin can change an approved ship's hours, with why, but not past what it took or below what's spent" do
    admin = users(:orpheus)
    Rails.configuration.x.admin_slack_ids, admins = [ admin.slack_id ], Rails.configuration.x.admin_slack_ids
    ship = ship_now(hours: 6)
    ship.update!(fraud_status: "good", fraud_score: 9)
    assert decide(ship, "approved", approved_hours: "6", justification: checked).persisted?
    assert ship.reload.approved?

    assert_not ShipReview.change_hours(ship, by: @reviewer, approved_hours: "4", justification: "Two hours were a tutorial.").persisted?
    change = ShipReview.change_hours(ship, by: admin, approved_hours: "4", justification: "short")
    assert_includes change.errors.full_messages, "Justification needs at least 10 characters: why the hours changed"
    change = ShipReview.change_hours(ship, by: admin, approved_hours: "7", justification: "Two hours were a tutorial.")
    assert_includes change.errors.full_messages, "Approved hours can't be more than the 6.0 it took"

    change = ShipReview.change_hours(ship, by: admin, approved_hours: "4", justification: "Two hours were a tutorial.")
    assert change.persisted?
    assert_equal 4, ship.reload.approved_hours
    assert_equal 4, @project.reload.hours_approved
    assert ship.approved?
    assert_equal "approved", ship.verdict.decision, "the call that decided it stands"
    assert_includes ShipReview.change_hours(ship, by: admin, approved_hours: "4", justification: "Two hours were a tutorial.").errors.full_messages,
                    "That's the hours it has already."

    waiting = ship_now(hours: 3, fraud: "unchecked")
    assert decide(waiting, "approved", approved_hours: "3", justification: checked).persisted?
    assert waiting.reload.awaiting_fraud?
    assert ShipReview.change_hours(waiting, by: admin, approved_hours: "2.5", justification: "Half an hour was idle.").persisted?
    assert_nil waiting.reload.approved_hours, "nothing's granted until the fraud check passes"
    FraudCheck.verdict(waiting, by: admin, score: "8", note: "Real heartbeats, real commits.")
    assert waiting.reload.approved?
    assert_equal 2.5, waiting.approved_hours
  ensure
    Rails.configuration.x.admin_slack_ids = admins
  end

  test "a ship from before today's rules, with no screenshot and a short description, can still be decided" do
    ship = ship_now(hours: 3)
    ship.screenshot.purge
    ship.update_column(:description, "tiny")
    assert_not ship.reload.valid?, "the maker couldn't submit it like this now"

    assert decide(ship, "approved", approved_hours: "3", justification: checked).persisted?
    assert ship.reload.approved?
  end

  test "the most of any approved ship counts, since each counts every hour up to it" do
    first = ship_now(hours: 6)
    decide(first, "approved", approved_hours: "6", justification: checked)
    second = ship_now(hours: 11)
    decide(second, "approved", approved_hours: "10.5", justification: checked, deflation_reason: "half an hour of setup")
    assert_equal 10.5, @project.reload.hours_approved
  end

  test "asking for changes needs a note, and lets them ship again for a week, even after it's all closed" do
    ship = ship_now(hours: 3)
    assert_includes decide(ship, "changes_requested").errors.full_messages, "Note to maker needs at least 10 characters: they'll read it"

    travel_to(Time.utc(2026, 11, 10, 12)) do
      assert_not @project.may_ship?, "closed, for someone who's shipped"
      decide(ship, "changes_requested", note_to_maker: "The demo link 404s.", justification: "checked twice")
      assert ship.reload.changes_requested?
      assert_nil ship.approved_hours
      assert_equal Time.utc(2026, 11, 17).end_of_day, ship.changes_due_at, "a week from the day, where they are (UTC here)"
      assert @project.reload.may_ship?
      assert_not @project.shipped?
    end
    travel_to(Time.utc(2026, 11, 18, 1)) { assert_not @project.reload.may_ship?, "a week's gone" }
  end

  test "rejecting is final: no shipping again" do
    ship = ship_now(hours: 3)
    decide(ship, "rejected", note_to_maker: "This is a video, not a game.")
    assert ship.reload.rejected?
    travel_to(Program::DATES.begin) { assert_not @project.reload.may_ship?, "even while shipping's open" }
  end

  test "only reviewers decide, never their own ship, unless they're an admin" do
    ship = ship_now(hours: 3)
    @reviewer.update!(review_roles: [ "fraud" ])
    assert_equal [ "You can't decide this one." ], decide(ship, "rejected", note_to_maker: "Not a game at all.").errors.full_messages

    users(:orpheus).update!(review_roles: [ "reviewer" ])
    assert_not ShipReview.decide(ship, by: users(:orpheus), decision: "approved", approved_hours: "3", justification: checked).persisted?
    assert ship.reload.in_review?

    with_admins("U0ORPHEUS") do
      assert ShipReview.decide(ship, by: users(:orpheus), decision: "approved", approved_hours: "3", justification: checked).persisted?
    end
  end

  test "Clippy DMs them the decision, with the reviewer's note and never the justification" do
    ship = ship_now(hours: 6)
    decide(ship, "approved", approved_hours: "5.5", justification: checked, deflation_reason: "half an hour of setup",
                             note_to_maker: "The second level is great.")
    assert_equal [ "U0ORPHEUS", "*Beat Sheet* is approved. 5.5 hrs are yours to spend in the shop.\n>The second level is great.\n" \
                                ":clippy-proud: clippy is quietly proud. :yay:", { "link" => [ "Open the shop", "https://wrong.hackclub.com/shop" ] } ],
                 dm_args
    assert_not_nil users(:orpheus).reload.slack_dmed_at

    clear_enqueued_jobs
    travel_to(Time.utc(2026, 11, 3, 12)) do
      decide(ship_now(hours: 7), "changes_requested", note_to_maker: "The demo link 404s.\nAnd add a README.", justification: "secret")
    end
    assert_equal "*Beat Sheet* needs a few changes before it can be approved:\n>The demo link 404s.\n>And add a README.\n" \
                 "Make them and ship it again by Nov 10.\n:clippy-hopeful: clippy is rooting for round two. :blob-wiggle:", dm_args.second
    assert_equal [ "Ship it again", "https://wrong.hackclub.com/project/ship" ], dm_args.third["link"]

    clear_enqueued_jobs
    decide(ship_now(hours: 8), "rejected", note_to_maker: "It's someone else's game.")
    assert_equal "*Beat Sheet* wasn't approved, and it can't be shipped again:\n>It's someone else's game.\n" \
                 ":clippy-emotional: clippy is sad about this one. :crying_dino:", dm_args.second
  end

  test "an approval waits on the fraud check, and whichever comes second completes it" do
    ship = ship_now(hours: 6, fraud: "unchecked")
    decide(ship, "approved", approved_hours: "6", justification: checked)
    assert ship.reload.in_review?, "still in review, to them"
    assert ship.awaiting_fraud?
    assert_equal 0, @project.reload.hours_approved
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }, "nobody's told yet"
    assert_equal "It's approved already, and waiting on the fraud check.",
                 decide(ship, "rejected", note_to_maker: "Changed my mind.").errors.full_messages.first

    fraud = User.create!(hca_id: "ident!frida", first_name: "Frida", review_roles: [ "fraud" ])
    verdict = FraudCheck.verdict(ship, by: fraud, score: "8", note: "Real heartbeats, real commits.")
    assert verdict.persisted?
    assert ship.reload.approved?
    assert_equal [ "good", 8, 6, @reviewer ], [ ship.fraud_status, ship.fraud_score, ship.approved_hours, ship.decided_by ]
    assert_equal 6, @project.reload.hours_approved
    assert_match(/is approved\. 6 hrs are yours/, dm_args.second)
  end

  test "the fraud check first, then the approval completes it at once" do
    fraud = User.create!(hca_id: "ident!frida", first_name: "Frida", review_roles: [ "fraud" ])
    ship = ship_now(hours: 6, fraud: "unchecked")
    FraudCheck.verdict(ship, by: fraud, score: "6", note: "Some odd hours, but fine.")
    assert_equal "sus", ship.reload.fraud_status, "5 to 7 passes, marked sus"
    assert ship.in_review?

    decide(ship, "approved", approved_hours: "6", justification: checked)
    assert ship.reload.approved?
  end

  test "failing the fraud check rejects it, final, whatever a reviewer said, and they're told only that" do
    fraud = User.create!(hca_id: "ident!frida", first_name: "Frida", review_roles: [ "fraud" ])
    ship = ship_now(hours: 6, fraud: "unchecked")
    decide(ship, "approved", approved_hours: "6", justification: checked)

    assert_includes FraudCheck.verdict(ship, by: fraud, score: "3", note: "x").errors.full_messages, "Justification needs at least 10 characters: what you saw"
    assert_includes FraudCheck.verdict(ship, by: fraud, score: "11", note: "Heartbeats from a script.").errors.full_messages, "Trust score should be 1 to 10"
    verdict = FraudCheck.verdict(ship, by: fraud, score: "3", note: "Heartbeats from a script, every 30s.")
    assert verdict.persisted?
    assert ship.reload.rejected?
    assert_equal [ "fraud", 3, nil, fraud ], [ ship.fraud_status, ship.fraud_score, ship.approved_hours, ship.decided_by ]
    assert_not @project.reload.may_ship?
    assert_equal "*Beat Sheet* wasn't approved, and it can't be shipped again:\n>#{FraudCheck::REJECT_NOTE}\n" \
                 ":clippy-emotional: clippy is sad about this one. :crying_dino:", dm_args.second
    assert_not_includes dm_args.second, "script"
    assert_equal "That one's been decided already.", FraudCheck.verdict(ship, by: fraud, score: "9", note: "On second thought.").errors.full_messages.first
  end

  test "only fraud reviewers check, never their own, and a reviewer can't" do
    ship = ship_now(hours: 2, fraud: "unchecked")
    assert_equal [ "You can't check this one." ], FraudCheck.verdict(ship, by: @reviewer, score: "9", note: "Looks real to me.").errors.full_messages
    users(:orpheus).update!(review_roles: [ "fraud" ])
    assert_equal [ "You can't check this one." ], FraudCheck.verdict(ship, by: users(:orpheus), score: "9", note: "Trust me, it's mine.").errors.full_messages
  end

  test "sending it on: to fraud, out of the review queue until it passes; to an admin, theirs to decide" do
    fraud = User.create!(hca_id: "ident!frida", first_name: "Frida", review_roles: [ "fraud" ])
    ship = ship_now(hours: 2, fraud: "unchecked")
    assert_includes decide(ship, "hold", hold: "fraud", justification: "hm").errors.full_messages, "Justification needs at least 10 characters: what they should look at"
    sent = decide(ship, "hold", hold: "fraud", justification: "The commits are all from one night.", note_to_maker: "not for them")
    assert_equal [ "send_fraud", nil ], [ sent.decision, sent.note_to_maker ]
    assert_equal [ "fraud", "The commits are all from one night." ], [ ship.reload.review_hold, ship.hold_note ]
    assert_not_includes ReviewQueue.waiting("review", @reviewer), ship
    assert_equal ship, ReviewQueue.waiting("fraud", fraud).first
    assert_nil ReviewQueue.next_for(fraud, queue: "fraud"), "never opened for you: opened from the list"
    assert_equal "It's been sent to fraud: it's back in the queue once the fraud check passes.",
                 decide(ship, "approved", approved_hours: "2", justification: checked).errors.full_messages.first
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }, "they're told nothing"

    FraudCheck.verdict(ship, by: fraud, score: "9", note: "One night, but a real one.")
    assert_nil ship.reload.review_hold
    assert_includes ReviewQueue.waiting("review", @reviewer), ship, "back in the review queue"

    decide(ship, "hold", hold: "admin", justification: "Not sure this counts as a game.")
    assert_not_includes ReviewQueue.waiting("review", @reviewer), ship
    with_admins("U0ORPHEUS") do
      assert_equal ship, ReviewQueue.waiting("review", users(:orpheus)).first, "admins see it, first"
      assert_equal "It's been sent to an admin, so it's theirs to decide.",
                   decide(ship, "rejected", note_to_maker: "Not a game at all.").errors.full_messages.first
    end
  end

  test "a reship keeps the last passing fraud check under 3 hours added, and starts again past it" do
    first = ship_now(hours: 4, fraud: "sus")
    first.update!(fraud_score: 6, status: "changes_requested")
    kept = @project.ships.create!(first.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 6.5, screenshot: upload, screenshot_shows_game: true))
    assert_equal [ "sus", 6 ], [ kept.fraud_status, kept.fraud_score ]
    assert_equal [ [ "fraud", "fraud_pass", nil ] ], kept.review_decisions.map { |decision| [ decision.queue, decision.decision, decision.reviewer ] }
    assert_match(/Kept from the ship before \(4\.0 hrs\)/, kept.review_decisions.first.justification)

    kept.update!(status: "changes_requested")
    again = @project.ships.create!(first.attributes.slice("title", "description", "repo_url", "demo_url").merge(hours: 9.5, screenshot: upload, screenshot_shows_game: true))
    assert again.fraud_unchecked?, "3 hours or more since the last check"
  end

  test "no DM to someone who stopped Clippy's messages" do
    users(:orpheus).update!(slack_muted_at: Time.current)
    decide(ship_now(hours: 2), "rejected", note_to_maker: "Not a game at all.")
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
  end

  private
    def decide(ship, decision, **attributes)
      ShipReview.decide(ship, by: @reviewer, decision:, **attributes)
    end

    def checked = "Played all three levels; the beat sync is in the formulas."

    def dm_args
      enqueued_jobs.select { |job| job[:job] == SlackMessageJob }.last[:args].then { |args| [ args[0], args[1], args[2].except("_aj_ruby2_keywords") ] }
    end

    def upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end

    def with_admins(*slack_ids)
      before = Rails.configuration.x.admin_slack_ids
      Rails.configuration.x.admin_slack_ids = slack_ids
      yield
    ensure
      Rails.configuration.x.admin_slack_ids = before
    end

    # Passed the fraud check already, unless it says otherwise, so an approval completes it.
    def ship_now(hours:, fraud: "good")
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                             screenshot_shows_game: true).tap { |ship| ship.update!(fraud_status: fraud) }
    end
end
