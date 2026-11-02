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

    def with_admins(*slack_ids)
      before = Rails.configuration.x.admin_slack_ids
      Rails.configuration.x.admin_slack_ids = slack_ids
      yield
    ensure
      Rails.configuration.x.admin_slack_ids = before
    end

    def ship_now(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"),
                             screenshot_shows_game: true)
    end
end
