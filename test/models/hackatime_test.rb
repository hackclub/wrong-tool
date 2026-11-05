require "test_helper"

class HackatimeTest < ActiveSupport::TestCase
  test "stats only count time since Hackatime time started counting" do
    assert_equal "/api/v1/users/my/stats?features=projects&start_date=2026-10-06", Hackatime.stats_path
  end

  test "projects need Hackatime linked" do
    assert_raises(Hackatime::NotLinked) { Hackatime.projects(users(:orpheus)) }
  end

  test "trust needs Hackatime linked, and is whatever Hackatime says of them" do
    assert_raises(Hackatime::NotLinked) { Hackatime.trust(users(:orpheus)) }

    before = Hackatime.stubbed_trust
    Hackatime.stubbed_trust = { "1001" => "yellow" }
    link_hackatime(users(:orpheus))
    assert_equal "yellow", Hackatime.trust(users(:orpheus))
    assert_equal "yellow", Hackatime.identity("token-orpheus").trust_level
    assert_equal "1001", Hackatime.identity("token-orpheus").uid
    assert_nil Hackatime.identity("nonsense"), "a token Hackatime doesn't know belongs to nobody"
  ensure
    Hackatime.stubbed_trust = before
  end

  test "trust levels read as what they mean, and anything new comes through as it is" do
    assert_equal "Hackatime doesn't trust their hours", Hackatime.trust_label("red")
    assert_equal "Hackatime has its doubts about them", Hackatime.trust_label("yellow")
    assert_equal "Hackatime hasn't scored them yet", Hackatime.trust_label("blue")
    assert_equal "Hackatime trusts them", Hackatime.trust_label("green")
    assert_equal "Hackatime calls them purple", Hackatime.trust_label("purple")
  end
  test "spans ask for each project whole, so a comma in its name is not a list of projects" do
    path = Hackatime.spans_path([ "Wrong 26, Snake, GS", "WebOS 1" ], start_date: Date.new(2026, 10, 5), end_date: Date.new(2026, 10, 15))
    assert_equal "/api/v1/users/my/heartbeats/spans?end_date=2026-10-15&project%5B%5D=Wrong+26%2C+Snake%2C+GS&project%5B%5D=WebOS+1&start_date=2026-10-05", path
  end
end
