require "test_helper"

class NudgeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "with time on hackatime and no project picked, Clippy asks you to pick one" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(hackatime_projects: [], repo_later: false)

    nudge = deliver(at_slot(9))

    assert_equal [ "setup", "hackatime_project" ], [ nudge.kind, nudge.arm ]
    assert_match(/pick your project/, nudge.text)
    assert_equal "#{Rails.configuration.x.app_url}/project", nudge.destination_url
    assert_equal Hackatime.stubbed_projects["1001"].map(&:name), @user.project.reload.hackatime_baseline, "noted what you had, like opening your project page would"
    assert_equal "bandit", deliver(at_slot(10)).kind, "the project step waits a few days before saying it again"
  end

  test "a new hackatime project gets linked for you instead of asked about" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(hackatime_projects: [], hackatime_baseline: [ "dotfiles" ])

    nudge = deliver(at_slot(9))

    assert_equal [ "rhythm-game" ], @user.project.reload.hackatime_projects
    assert_not_equal "hackatime_project", nudge&.arm
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/linked to \*A rhythm game in Spreadsheet\* now/, dm[:args].second)
  end

  test "nothing on hackatime to pick means nothing to ask" do
    sent!("first_session", kind: "milestone")
    @user.project.update!(hackatime_projects: [], repo_later: false)
    before = Hackatime.stubbed_projects
    Hackatime.stubbed_projects = before.merge("1001" => [])

    assert_equal "repo", deliver(at_slot(9)).arm
  ensure
    Hackatime.stubbed_projects = before
  end

  test "a pick-your-project nudge worked once a project's picked" do
    nudge = sent!("hackatime_project", kind: "setup", at: at_slot(8))
    travel_to(at_slot(11)) { Nudge.score_due }
    assert_equal 1, nudge.reload.reward

    @user.project.update!(hackatime_projects: [])
    nudge.score!
    assert_equal 0, nudge.reload.reward
  end

  test "the overtake copy knows who's just above you when they're within a session" do
    ana = users(:ana)
    ana.update!(hackatime_uid: "1002", hackatime_access_token: "token-heidi")
    ana.project.update!(hackatime_projects: [ "heidis-game" ])
    Hackatime.stubbed_spans["1002"] = [ span(at_slot(7, hour: 17), 120) ] # half an hour ahead of Orpheus
    at = at_slot(8)
    travel_to(at) do
      StreakActivity.sync_for_user!(ana)
      vars = Nudge::Context.new(@user.reload, at).tap(&:refresh!).vars
      assert_equal({ rank: 2, above: "pixelana", gap_minutes: 30 }, vars.slice(:rank, :above, :gap_minutes, :passed_by, :places_lost))
      assert Nudge::Copy.renderable?("overtake", vars)
      assert_includes Nudge::Bandit.new("behind").available_arms(Nudge::Context.new(@user, at)), "overtake"

      @user.project.update_columns(week_rank: 1, week_rank_on: at.to_date - 1) # Orpheus was first yesterday
      vars = Nudge::Context.new(@user.reload, at).vars
      assert_equal({ passed_by: "pixelana", places_lost: 1 }, vars.slice(:passed_by, :places_lost))

      Hackatime.stubbed_spans["1002"] = [ span(at_slot(7, hour: 17), 180) ] # too far ahead
      StreakActivity.sync_for_user!(ana.reload)
      vars = Nudge::Context.new(@user.reload, at).vars
      assert_equal({ rank: 2 }, vars.slice(:rank, :above, :gap_minutes, :passed_by))
      assert_not Nudge::Copy.renderable?("overtake", vars)
    end
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

  test "a setup nudge worked if the step it asked for got done, whether or not they built" do
    linked = sent!("hackatime", kind: "setup", at: at_slot(8)) # Hackatime's linked in setup
    no_repo = sent!("repo", kind: "setup", at: at_slot(9))
    @user.project.update!(repo_later: false)
    Hackatime.stubbed_spans = { "1001" => [ span(at_slot(9, hour: 20), 30) ] } # built, but no repo added

    travel_to(at_slot(11)) { Nudge.score_due }

    assert_equal [ 1, 0 ], [ linked, no_repo ].map { |nudge| nudge.reload.reward }
  end

  test "setup nudges scored on building can be rescored on their step" do
    linked = sent!("hackatime", kind: "setup", at: at_slot(8))
    linked.update!(reward: 0, rewarded_at: at_slot(9))
    stopped = sent!("repo", kind: "setup", at: at_slot(8))
    stopped.update!(reward: Nudge::OPT_OUT_PENALTY, opted_out_at: at_slot(8, hour: 20), rewarded_at: at_slot(9))
    unscored = sent!("repo", kind: "setup", at: at_slot(10))

    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("nudges:rescore_setup")
    travel_to(at_slot(11)) { capture_io { Rake::Task["nudges:rescore_setup"].execute } }

    assert_equal [ 1, Nudge::OPT_OUT_PENALTY, nil ], [ linked, stopped, unscored ].map { |nudge| nudge.reload.reward }
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
