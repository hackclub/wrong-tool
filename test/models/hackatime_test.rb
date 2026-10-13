require "test_helper"

class HackatimeTest < ActiveSupport::TestCase
  test "stats only count time since Hackatime time started counting" do
    assert_equal "/api/v1/users/my/stats?features=projects&start_date=2026-10-06", Hackatime.stats_path
  end

  test "projects need Hackatime linked" do
    assert_raises(Hackatime::NotLinked) { Hackatime.projects(users(:orpheus)) }
  end
  test "spans ask for each project whole, so a comma in its name is not a list of projects" do
    path = Hackatime.spans_path([ "Wrong 26, Snake, GS", "WebOS 1" ], start_date: Date.new(2026, 10, 5), end_date: Date.new(2026, 10, 15))
    assert_equal "/api/v1/users/my/heartbeats/spans?end_date=2026-10-15&project%5B%5D=Wrong+26%2C+Snake%2C+GS&project%5B%5D=WebOS+1&start_date=2026-10-05", path
  end
end
