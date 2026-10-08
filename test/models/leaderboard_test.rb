require "test_helper"

class LeaderboardTest < ActiveSupport::TestCase
  setup do
    @orpheus, @ana = users(:orpheus), users(:ana)
    link_hackatime(@orpheus)
    @ana.update!(hackatime_uid: "1002", hackatime_access_token: "token-heidi")
    @orpheus.project.update!(hackatime_projects: [ "rhythm-game" ])
    @ana.project.update!(hackatime_projects: [ "heidis-game" ])
    # Day two of week one: Orpheus built 1.5 hours, Ana 2.
    at = Time.utc(2026, 10, 7, 15)
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(at, 90) ], "1002" => [ hackatime_span(at, 120) ] }
    travel_to(Time.utc(2026, 10, 8, 12))
    [ @orpheus, @ana ].each { |user| StreakActivity.sync_for_user!(user) }
  end

  teardown do
    travel_back
    Hackatime.stubbed_spans = {}
  end

  test "everyone set up, by hours this week, with who's just above and how far" do
    first, second = Leaderboard.places

    assert_equal [ @ana.project, 1, nil ], [ first.project, first.rank, first.above ]
    assert_equal [ @orpheus.project, 2, @ana.project ], [ second.project, second.rank, second.above ]
    assert_nil first.gap_minutes
    assert_equal 30, second.gap_minutes
    assert_equal second, Leaderboard.place_of(@orpheus.project)
  end

  test "someone not set up isn't on it" do
    @ana.project.update!(hackatime_projects: [])
    @ana.update!(hackatime_uid: nil, hackatime_access_token: nil)
    assert_equal [ @orpheus.project ], Leaderboard.places.map(&:project)
  end

  test "a snapshot notes where everyone was, and the board shows how far they've moved since" do
    Leaderboard.snapshot!(Date.new(2026, 10, 7))
    assert_equal [ 1, Date.new(2026, 10, 7) ], [ @ana.project.reload.week_rank, @ana.project.week_rank_on ]
    assert_equal 2, @orpheus.project.reload.week_rank

    # Orpheus builds another hour and passes Ana.
    Hackatime.stubbed_spans["1001"] << hackatime_span(Time.utc(2026, 10, 8, 9), 60)
    StreakActivity.sync_for_user!(@orpheus.reload)

    orpheus, ana = Leaderboard.places
    assert_equal [ @orpheus.project, 1 ], [ orpheus.project, orpheus.change ]
    assert_equal [ @ana.project, -1 ], [ ana.project, ana.change ]
  end

  test "a snapshot from another week says nothing: week hours start over" do
    Leaderboard.snapshot!(Date.new(2026, 10, 7))
    travel_to(Time.utc(2026, 10, 13, 12))
    assert_nil Leaderboard.place_of(@orpheus.project).change
  end
end
