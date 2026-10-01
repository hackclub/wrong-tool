require "test_helper"

class HallsControllerTest < ActionDispatch::IntegrationTest
  test "anyone can see every wrong tool, red where nothing's shipped yet" do
    get hall_path

    assert_response :success
    assert_equal %w[Spreadsheet Figma Email SSH Shaders], css_select(".hall__tool").map(&:text)
    assert_select ".hall__nothing", "Nothing yet in Spreadsheet, Figma, Email, SSH or Shaders."
    assert_select "tr[data-empty]", 5
    assert_select "tr", text: /Spreadsheet.*1 person building one/m
    assert_select ".hall__mine", count: 0
    assert_select ".sheet-tab", /Onboarding/
  end

  test "signed in, the tool you're building in is yours" do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub"
    follow_redirect!
    get hall_path

    assert_select "tr[data-you] .hall__tool", "Spreadsheet"
    assert_select "tr[data-you] .hall__mine", "You're building here"
    assert_select ".sheet-tab[aria-current=page]", /Hall of Wrong/
    assert_select ".sheet-tab", text: /Onboarding/, count: 0
  end
end
