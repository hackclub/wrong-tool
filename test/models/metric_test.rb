require "test_helper"

class MetricTest < ActiveSupport::TestCase
  setup do
    @orpheus = users(:orpheus)
    @orpheus.streak_activities.create!(activity_date: Date.new(2026, 10, 6), coded_seconds: 3 * 3600)
    @orpheus.streak_activities.create!(activity_date: Date.new(2026, 10, 7), coded_seconds: 25 * 60)
    @orpheus.update!(current_streak: 2)
    User.update_all(created_at: Time.utc(2026, 10, 6, 9)) # fixtures are made now, which is after the days here
  end

  test "a day's numbers are as of the end of it, and the undated ones are only taken for today" do
    travel_to Time.utc(2026, 10, 7, 20)

    day6 = Metric.values(Date.new(2026, 10, 6))
    assert_equal [ 1, 3.0, 3.0, 1, 0, 1 ], day6.values_at("builders", "hours_day", "hours", "first_20", "past_5h", "completed")
    assert_not day6.key?("on_streak"), "undated numbers aren't guessed for past days"

    today = Metric.values
    assert_equal [ 1, 0.4, 3.4, 1, 1 ], today.values_at("builders", "hours_day", "hours", "completed", "on_streak")
    assert_equal User.count, today["signed_in"]
  end

  test "snapshots are written once per day and metric, and today's is rewritten" do
    travel_to Time.utc(2026, 10, 7, 20)
    Metric.snapshot!
    @orpheus.streak_activities.find_by(activity_date: Date.new(2026, 10, 7)).update!(coded_seconds: 3600)
    Metric.snapshot!

    assert_equal 1, MetricSnapshot.where(day: Date.new(2026, 10, 7), key: "hours_day").count
    assert_equal 1.0, MetricSnapshot.find_by(day: Date.new(2026, 10, 7), key: "hours_day").value
  end

  test "the backfill writes every day of wrong tool so far, and history reads them back" do
    travel_to Time.utc(2026, 10, 8, 12)
    Metric.backfill!

    days, values = Metric.history
    assert_equal [ Date.new(2026, 10, 6), Date.new(2026, 10, 7), Date.new(2026, 10, 8) ], days
    assert_equal [ 3.0, 3.4, 3.4 ], days.map { |day| values["hours"][day] }
    assert_equal [ nil, nil, 1 ], days.map { |day| values["on_streak"][day] }
  end
end
