require "test_helper"

class RewardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @orpheus, @ana = users(:orpheus), users(:ana)
  end

  # Days in October someone built `minutes` on.
  def built(user, days, minutes: 20)
    days.each { |day| user.streak_activities.create!(activity_date: Date.new(2026, 10, day), coded_seconds: minutes * 60) }
  end

  def slack_messages
    enqueued_jobs.select { |job| job[:job] == SlackMessageJob }.map { |job| job[:args].first(2) }
  end

  test "streak rewards are earned once, as the streak reaches them, and each sends a DM" do
    built(@orpheus, 6..10)
    travel_to(Time.utc(2026, 10, 10, 12)) { @orpheus.recalculate_streak! }

    assert_equal %w[flame gold_star], @orpheus.rewards.pluck(:key).sort
    assert_includes slack_messages, [ "U0ORPHEUS", "3-day streak. Clippy now wears a gold star on your sheet." ]

    travel_to(Time.utc(2026, 10, 10, 13)) { @orpheus.recalculate_streak! }
    assert_equal 2, @orpheus.rewards.count
  end

  test "5 logged hours earns a shoutout in #wrong, once" do
    @orpheus.project.update!(hackatime_projects: [ "rhythm-game" ])
    link_hackatime(@orpheus)
    built(@orpheus, 6..8, minutes: 90) # 4.5 hours
    travel_to(Time.utc(2026, 10, 8, 12)) { @orpheus.recalculate_streak! }
    assert_not @orpheus.earned?("hours_shoutout")

    built(@orpheus, [ 9 ], minutes: 30)
    travel_to(Time.utc(2026, 10, 9, 12)) { @orpheus.recalculate_streak! }

    assert @orpheus.reload.earned?("hours_shoutout")
    assert_includes slack_messages, [ "U0ORPHEUS", "5 hours logged. We posted *#{@orpheus.project.title}* in #wrong." ]
    assert_includes slack_messages, [ Program::SLACK_CHANNEL_ID, ":yay: <@U0ORPHEUS> just logged 5 hours on *#{@orpheus.project.title}*, built in " \
                                                                  "#{@orpheus.project.tool_name}. halfway to a handheld.\n_clippy is doing a little dance. :dino-bbq:_" ]

    travel_to(Time.utc(2026, 10, 9, 13)) { @orpheus.recalculate_streak! }
    assert_equal 1, @orpheus.rewards.where(key: "hours_shoutout").count
  end

  test "rewards earned quietly say nothing, so a backfill can post one roundup" do
    [ @orpheus, @ana ].each do |user|
      user.project.update!(hackatime_projects: [ "game" ])
      user.update!(hackatime_uid: "hackatime-#{user.id}", hackatime_access_token: "token")
      built(user, 6..8, minutes: 120)
    end
    Reward.quietly { [ @orpheus, @ana ].each { |user| travel_to(Time.utc(2026, 10, 8, 12)) { user.recalculate_streak! } } }
    assert_empty slack_messages
    assert_not Reward.quiet

    RewardNotifier.roundup_hours_shoutouts(Reward.where(key: "hours_shoutout").order(:user_id).to_a)
    assert_equal 1, slack_messages.count { |channel, _| channel == Program::SLACK_CHANNEL_ID }
    assert_includes slack_messages, [ Program::SLACK_CHANNEL_ID, ":yay: 5 hours logged since kickoff, by <@U0ORPHEUS> (*#{@orpheus.project.title}*) and " \
                                                                  "<@U0ANA> (*#{@ana.project.title}*). halfway to a handheld, every one of them.\n_clippy is overwhelmed. :cat-woah:_" ]
    assert_equal 2, slack_messages.count { |channel, _| channel != Program::SLACK_CHANNEL_ID }
  end

  test "the backfill syncs everyone, awards the shoutouts, and posts one roundup" do
    @orpheus.project.update!(hackatime_projects: [ "rhythm-game" ])
    link_hackatime(@orpheus)
    at = Time.utc(2026, 10, 7, 12)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(at, 200), hackatime_span(at + 1.day, 200) ] } # 6.7 hours
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("rewards:backfill_hours_shoutouts")

    travel_to(Time.utc(2026, 10, 8, 15)) { capture_io { Rake::Task["rewards:backfill_hours_shoutouts"].execute } }

    assert @orpheus.reload.earned?("hours_shoutout")
    assert_not @ana.earned?("hours_shoutout")
    posts = slack_messages.select { |channel, _| channel == Program::SLACK_CHANNEL_ID }
    assert_equal 1, posts.size
    assert_match(/by <@U0ORPHEUS> \(\*.*\*\)\. halfway/, posts.first.last)
  ensure
    Hackatime.stubbed_spans = {}
  end

  test "hours don't count towards a shoutout without Hackatime linked" do
    built(@orpheus, 6..8, minutes: 120)
    travel_to(Time.utc(2026, 10, 8, 12)) { @orpheus.recalculate_streak! }
    assert_not @orpheus.earned?("hours_shoutout")
  end

  test "after 7 days, the first day you miss is covered, and the next one isn't" do
    built(@orpheus, [ *6..12, 14, 15 ])
    travel_to(Time.utc(2026, 10, 15, 12)) do
      @orpheus.recalculate_streak!
      assert_equal 9, @orpheus.current_streak
      assert_equal Date.new(2026, 10, 13), @orpheus.streak_skip_used_on
      assert @orpheus.streak_week.find { |day| day[:date] == Date.new(2026, 10, 13) }[:skipped]
    end

    travel_to(Time.utc(2026, 10, 17, 12)) { @orpheus.recalculate_streak! }
    assert_equal 0, @orpheus.current_streak
  end

  test "before 7 days there's no skip day" do
    built(@orpheus, [ 6, 7, 8, 10 ])
    travel_to(Time.utc(2026, 10, 10, 12)) { @orpheus.recalculate_streak! }
    assert_equal 1, @orpheus.current_streak
    assert_nil @orpheus.streak_skip_used_on
  end

  test "a pair week is a program week you both log 4h in, and earns stickers" do
    pair = projects(:orpheus).pair_with(projects(:ana))
    built(@orpheus, [ 6, 7 ], minutes: 120)
    built(@ana, [ 8 ], minutes: 180)
    travel_to(Time.utc(2026, 10, 9, 12)) do
      @orpheus.recalculate_streak!
      assert_equal 0, pair.pair_weeks

      built(@ana, [ 9 ], minutes: 60)
      @ana.recalculate_streak!
      assert_equal 1, pair.pair_weeks
      assert_equal [ "stickers" ], pair.rewards.pluck(:key)
      assert_includes slack_messages, [ "U0ANA", "You and <@U0ORPHEUS> both logged 4h this week. You'll each get a sticker sheet with your handheld." ]
    end
  end

  test "the desktop background goes to the first pair to 10h each, and only them" do
    pair = projects(:orpheus).pair_with(projects(:ana))
    built(@orpheus, 6..10, minutes: 120)
    built(@ana, 6..10, minutes: 120)
    travel_to(Time.utc(2026, 10, 10, 12)) { @ana.recalculate_streak! }

    assert_equal pair, Reward.desktop_pair
    assert_includes slack_messages,
                    [ "C0C5UHLAAP5", "<@U0ANA> and <@U0ORPHEUS> were the first pair to log 10h each. They'll pick Kartikey's desktop background." ]
    assert_raises(ActiveRecord::RecordNotUnique) { Reward.create!(pair: Pair.new, key: "desktop") }
  end

  test "Slack messages render as blocks with a button" do
    rendered = ApplicationController.renderer.new.render(template: "slack/message", formats: [ :slack_message ],
                                                          locals: { text: "hi", link: [ "Open wrong tool", "https://wrong.hackclub.com/project" ] })
    blocks = JSON.parse(rendered)["blocks"]
    assert_equal "hi", blocks[0]["text"]["text"]
    assert_equal "https://wrong.hackclub.com/project", blocks[1]["elements"][0]["url"]
  end
end
