require "test_helper"

class PublicStatsTest < ActiveSupport::TestCase
  # More builders on Figma.
  def add_builders(count = 3, tool: "figma", hours: 2)
    count.times.map do |index|
      user = User.create!(hca_id: "ident!builder#{index}", first_name: "Builder#{index}", current_streak: index + 1,
                          hackatime_uid: "90#{index}", hackatime_access_token: "token")
      user.create_project!(tool:, tool_name: tool.capitalize, idea: "a game", prize: "miyoo", pace_minutes: 45,
                           build_time: "evening", signed_on: Program::DATES.begin, hackatime_projects: [ "game" ])
      user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: hours * 3600)
      user
    end
  end

  test "exact numbers, even small ones" do
    travel_to Program::DATES.begin + 1 do
      stats = PublicStats.new.to_h

      assert_equal 2, stats[:totals][:builders], "the two projects in the fixtures"
      assert_equal 0.0, stats[:totals][:hours]
      assert_equal [ 2, 2 ], stats[:funnel].first(2).map { |step| step[:count] }
      assert_equal 1.0, stats[:funnel].first[:share]
      assert_equal 1, stats[:tools].find { |tool| tool[:label] == "Figma" }[:builders]
      assert_nil stats[:streaks][:longest], "nobody's on a streak"
    end
  end

  test "the totals, the funnel, the days, the tools and the streaks" do
    add_builders(3, hours: 6)

    travel_to Program::DATES.begin + 1 do
      stats = PublicStats.new.to_h

      assert_equal 5, stats[:totals][:builders]
      assert_equal 18.0, stats[:totals][:hours]
      assert_equal [ 5, 5, 3, 3, 3, 3, 0, 0 ], stats[:funnel].map { |step| step[:count] }
      assert_in_delta 0.6, stats[:funnel][2][:share]

      first_day = stats[:daily].first
      assert_equal [ 18.0, 3 ], first_day.values_at(:hours, :builders)
      assert stats[:daily].last[:future]

      figma = stats[:tools].find { |tool| tool[:label] == "Figma" }
      assert_equal [ 4, 18.0 ], figma.values_at(:builders, :hours), "ana's fixture project is Figma too"
      assert_equal 1, stats[:tools].find { |tool| tool[:label] == "Spreadsheets" }[:builders]

      assert_equal [ 3, 3 ], stats[:streaks].values_at(:on_streak, :longest)
    end
  end
end
