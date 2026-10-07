require "test_helper"

class StreakActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:orpheus)
    link_hackatime(@user)
    @user.project.update!(hackatime_projects: [ "rhythm-game" ])
  end

  teardown { Hackatime.stubbed_spans = {} }

  # A span of `minutes` starting at `at`, as Hackatime sends it.
  def span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  test "days in a row with 20 minutes make the streak, and today doesn't break it until it's over" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [
        span(Time.utc(2026, 10, 9, 15), 25), # Fri
        span(Time.utc(2026, 10, 10, 15), 20), # Sat
        span(Time.utc(2026, 10, 11, 15), 30)  # Sun; nothing yet today
      ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 3, @user.reload.current_streak
      assert_equal 3, @user.project.streak
    end
  end

  test "a day under 20 minutes breaks it" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [
        span(Time.utc(2026, 10, 9, 15), 25),
        span(Time.utc(2026, 10, 10, 15), 10),
        span(Time.utc(2026, 10, 11, 15), 30),
        span(Time.utc(2026, 10, 12, 9), 20)
      ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 2, @user.reload.current_streak
    end
  end

  test "building past midnight counts for the night before" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 12, 1), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 11)).coded_seconds
      assert_equal 1, @user.reload.current_streak
    end
  end

  test "a span across 2am is split between the two days" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 12, 1, 50), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal 10 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 11)).coded_seconds
      assert_equal 20 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 12)).coded_seconds
    end
  end

  test "days follow your timezone" do
    @user.update!(timezone: "America/New_York")
    travel_to Time.utc(2026, 10, 12, 12) do
      # 9pm on the 11th in New York, 1am on the 12th in UTC.
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 12, 1), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 11)).completed?
    end
  end

  test "tonight's building counts today, even where Hackatime's day has already ended" do
    @user.update!(timezone: "America/Los_Angeles")
    asked = nil
    spans = Hackatime.method(:heartbeat_spans)
    Hackatime.define_singleton_method(:heartbeat_spans) { |user, names, start_date:, end_date:| asked = [ start_date, end_date ]; spans.call(user, names, start_date:, end_date:) }

    # 8pm on the 11th in Los Angeles: already the 12th by Hackatime's clock.
    travel_to Time.utc(2026, 10, 12, 3, 30) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 12, 3), 30) ] }
      StreakActivity.sync_for_user!(@user)

      assert_equal [ Date.new(2026, 10, 5), Date.new(2026, 10, 13) ], asked, "a day either side of the streak days"
      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 11)).coded_seconds
      assert_equal 0.5, @user.project.hours_logged
      assert_equal 0.5, @user.project.hours_this_week
    end
  ensure
    Hackatime.define_singleton_method(:heartbeat_spans, spans)
  end

  test "the next sync goes over the day before too, in case Hackatime's spans moved" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 11, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal 30 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 11)).coded_seconds
    end

    travel_to Time.utc(2026, 10, 12, 18) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 11, 15), 45) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal 45 * 60, @user.streak_activities.find_by(activity_date: Date.new(2026, 10, 11)).coded_seconds
    end
  end

  test "nothing syncs until you've picked Hackatime projects to track" do
    @user.project.update!(hackatime_projects: [])
    Hackatime.stubbed_spans = { "1001" => [ span(Time.current - 1.hour, 30) ] }

    assert_nil StreakActivity.sync_for_user!(@user)
    assert_empty @user.streak_activities
  end

  test "the week shows which days you hit 20 minutes" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 11, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)

      week = @user.streak_week
      assert_equal %w[S M T W T F S], week.map { |day| day[:letter] }
      assert_equal [ true, false ], week.first(2).map { |day| day[:completed] }
      assert week[1][:today]
    end
  end

  test "changing your Hackatime projects rebuilds the streak from the start" do
    travel_to Time.utc(2026, 10, 12, 12) do
      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 11, 15), 30) ] }
      StreakActivity.sync_for_user!(@user)
      assert_equal 1, @user.reload.current_streak

      Hackatime.stubbed_spans = { "1001" => [ span(Time.utc(2026, 10, 10, 15), 30), span(Time.utc(2026, 10, 11, 15), 30) ] }
      perform_enqueued_jobs { @user.project.update!(hackatime_projects: [ "rhythm-game", "beat-sheet-art" ]) }

      assert_equal 2, @user.reload.current_streak
    end
  end

  test "with no Hackatime projects left, there's no streak" do
    @user.streak_activities.create!(activity_date: Date.current, coded_seconds: 30 * 60)
    @user.update_column(:current_streak, 1)

    @user.project.update_column(:hackatime_projects, [])
    @user.refresh_streak!

    assert_equal 0, @user.reload.current_streak
    assert_empty @user.streak_activities
  end
end
