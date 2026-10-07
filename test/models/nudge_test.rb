require "test_helper"

class NudgeTest < ActiveSupport::TestCase
  SlackMessage = Struct.new(:channel, :ts)

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true)
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(7, hour: 17), 90) ] } # 1.5 hours, on day two

    @sent = []
    sent = @sent
    @dm = SlackBot.method(:dm)
    SlackBot.define_singleton_method(:dm) { |slack_id, text:, blocks:| sent << [ slack_id, text, blocks ] && SlackMessage.new("D0ORPHEUS", "1.0") }
  end

  teardown do
    SlackBot.define_singleton_method(:dm, @dm)
    Hackatime.stubbed_spans = {}
  end

  # Orpheus builds in the evening: 7pm in New York.
  def at_slot(day = 8, hour: 19, min: 5)
    Time.find_zone("America/New_York").local(2026, 10, day, hour, min)
  end

  def deliver(at = at_slot)
    travel_to(at) { Nudge.deliver_to(@user.reload, at) }
  end

  def sent!(arm, kind: "bandit", at: at_slot(7))
    @user.nudges.create!(kind:, arm:, delivered: true, sent_at: at)
  end

  def span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  test "wrong tool's first day starts with the kickoff" do
    nudge = deliver(at_slot(6))

    assert_equal [ "program", "kickoff" ], [ nudge.kind, nudge.arm ]
    assert nudge.delivered
    assert_equal [ "D0ORPHEUS", "1.0" ], [ nudge.slack_channel, nudge.slack_ts ]
    assert_equal "U0ORPHEUS", @sent.sole.first
  end

  test "then milestones, then setup steps, before the bandit" do
    assert_equal "first_session", deliver.arm

    sent!("first_session", kind: "milestone")
    @user.project.update!(repo_later: false)
    assert_equal "repo", deliver(at_slot(9)).arm

    sent!("repo", kind: "setup", at: at_slot(9))
    assert_equal "bandit", deliver(at_slot(10)).kind, "the repo nudge waits a few days before saying it again"
  end

  test "the bandit picks an arm that fits where you are, and logs the odds it picked it at" do
    sent!("first_session", kind: "milestone")
    nudge = deliver(at_slot(10))

    assert_equal "lapsed", nudge.bucket # 1.5 hours, but nothing in the last couple of days
    assert_includes Nudge::Bandit::ARMS["lapsed"], nudge.arm
    assert_operator nudge.propensity, :>, 0
    assert nudge.text.present?
    assert_equal Nudge::Copy.mood_for(nudge.arm), nudge.mood
  end

  test "nothing outside your slot, quiet hours, wrong tool's dates, or once Clippy's stopped" do
    assert_nil deliver(at_slot(8, hour: 18))
    assert_nil deliver(at_slot(8, hour: 19, min: 15))
    assert_nil deliver(at_slot(5))
    assert_nil deliver(at_slot(21))

    @user.update!(slack_muted_at: Time.current)
    assert_nil deliver
    assert_empty @sent
  end

  test "nothing if you've had one today, or already built today" do
    sent!("first_session", kind: "milestone", at: at_slot(8, hour: 9))
    assert_nil deliver

    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8, hour: 17), 25) ] }
    @user.nudges.delete_all
    assert_nil deliver
  end

  test "a DM that doesn't go stops Clippy trying" do
    SlackBot.define_singleton_method(:dm) { |*, **| nil }
    configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    assert_not deliver.delivered
    assert @user.reload.slack_dm_failed_at
  ensure
    Rails.configuration.x.slack_configured = configured
  end

  test "a nudge worked if you built 20 minutes in the six hours after it" do
    worked = sent!("tiny_step", at: at_slot(8))
    didnt = sent!("pledge", at: at_slot(9))
    opted_out = sent!("dramatic", at: at_slot(10))
    opted_out.update!(opted_out_at: at_slot(10) + 1.minute)
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8, hour: 21), 25), span(at_slot(9, hour: 18), 30) ] }

    travel_to(at_slot(11)) { Nudge.score_due }

    assert_equal [ 1, 0, Nudge::OPT_OUT_PENALTY ], [ worked, didnt, opted_out ].map { |nudge| nudge.reload.reward }
  end

  test "scoring tells PostHog how the nudge did" do
    nudge = sent!("tiny_step", at: at_slot(8))
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(8, hour: 21), 25) ] }
    captured = []
    original, configured = PostHog.method(:capture), Rails.configuration.x.posthog_configured
    PostHog.define_singleton_method(:capture) { |**event| captured << event }
    Rails.configuration.x.posthog_configured = true

    travel_to(at_slot(11)) { Nudge.score_due }

    event = captured.find { |each| each[:event] == "nudge_scored" }
    assert_equal({ nudge_id: nudge.id, arm: "tiny_step", reward: 1, worked: true, built_minutes: 25 },
                 event[:properties].slice(:nudge_id, :arm, :reward, :worked, :built_minutes))
  ensure
    PostHog.define_singleton_method(:capture, original)
    Rails.configuration.x.posthog_configured = configured
  end

  test "the window has to close before a nudge is scored" do
    nudge = sent!("tiny_step", at: at_slot(8))
    travel_to(at_slot(8, hour: 23)) { Nudge.score_due }
    assert_nil nudge.reload.reward
  end
end
