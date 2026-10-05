require "test_helper"

class HackatimeTest < ActiveSupport::TestCase
  test "stats only count time since Hackatime time started counting" do
    assert_equal "/api/v1/users/my/stats?features=projects&start_date=2026-10-06", Hackatime.stats_path
  end

  test "projects need Hackatime linked" do
    assert_raises(Hackatime::NotLinked) { Hackatime.projects(users(:orpheus)) }
  end
end
