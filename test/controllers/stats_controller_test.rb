require "test_helper"

class StatsControllerTest < ActionDispatch::IntegrationTest
  test "anyone can see wrong tool in numbers, with small groups hidden and nobody named" do
    get stats_path

    assert_response :success
    assert_select "h1", "wrong tool in numbers"
    assert_select ".stats__tile", text: /Builders\s*<3/
    assert_select ".stats__bars th", "Linked Hackatime"
    assert_select ".stats__column", Program::DATES.count
    assert_no_match(/Orpheus|Ana\b|Lovelace|orph|pixelana/, response.body)
  end
end
