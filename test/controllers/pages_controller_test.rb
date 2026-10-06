require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home renders a tab and a section per sheet, with Hero open" do
    get root_path

    assert_response :success
    assert_select ".sheet-tab", 5
    assert_select ".sheet-tab[aria-current=page]", text: /Hero/
    assert_select ".sheet__section", 5
    assert_select ".sheet__section:not([hidden])#hero"
  end

  test "gives iOS a home screen icon and name" do
    get root_path

    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png'][sizes='180x180']"
    assert_select "meta[name=apple-mobile-web-app-title][content='wrong tool']"
  end

  test "signed in, the landing page sends you to onboarding, or your project once you've pledged" do
    sign_in_as(mock_hack_club_auth)
    get root_path
    assert_redirected_to onboarding_path

    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get root_path
    assert_redirected_to project_path
  end

  test "someone who's pledged signs in from the landing page and lands on their project, skipping onboarding" do
    get root_path
    assert_select "form.app-bar__sign-in[action='/auth/hackclub'] input[name=origin][value='/']"

    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
    post "/auth/hackclub", params: { origin: root_path }
    follow_redirect!
    assert_redirected_to root_path
    follow_redirect!
    assert_redirected_to project_path
  end

  private
    def sign_in_as(_auth)
      post "/auth/hackclub"
      follow_redirect!
    end
end
