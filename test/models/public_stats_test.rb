require "test_helper"

class PublicStatsTest < ActiveSupport::TestCase
  # Three more builders on Figma, so there's enough of them to show.
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

  test "groups under three people don't show, hours included" do
    travel_to Program::DATES.begin + 1 do
      stats = PublicStats.new.to_h

      assert_nil stats[:totals][:builders], "only two projects in the fixtures"
      assert_nil stats[:totals][:hours]
      assert_equal [ nil ], stats[:tools].map { |tool| tool[:builders] }.uniq
      assert stats[:funnel].all? { |step| step[:count].nil? && step[:share].nil? }
    end
  end

  test "with enough people, the totals, the funnel, the days, the tools and the streaks" do
    add_builders(3, hours: 6)

    travel_to Program::DATES.begin + 1 do
      stats = PublicStats.new.to_h

      assert_equal 5, stats[:totals][:builders]
      assert_equal 18, stats[:totals][:hours]
      assert_equal [ 5, 5, 3, 3, 3, 3, nil, nil ], stats[:funnel].map { |step| step[:count] }
      assert_in_delta 0.6, stats[:funnel][2][:share]

      first_day = stats[:daily].first
      assert_equal [ 18.0, 3 ], first_day.values_at(:hours, :builders)
      assert stats[:daily].last[:future]

      figma = stats[:tools].find { |tool| tool[:label] == "Figma" }
      assert_equal [ 4, 18 ], figma.values_at(:builders, :hours), "ana's fixture project is Figma too"
      assert_nil stats[:tools].find { |tool| tool[:label] == "Spreadsheets" }[:builders]

      assert_equal [ 3, 3 ], stats[:streaks].values_at(:on_streak, :longest)
    end
  end
end
