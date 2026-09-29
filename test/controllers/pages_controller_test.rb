require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home renders a tab and a section per sheet, with Hero open" do
    get root_path

    assert_response :success
    assert_select ".sheet-tab", 4
    assert_select ".sheet-tab[aria-current=page]", text: /Hero/
    assert_select ".sheet__section", 4
    assert_select ".sheet__section:not([hidden])#hero"
  end

  test "gives iOS a home screen icon and name" do
    get root_path

    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png'][sizes='180x180']"
    assert_select "meta[name=apple-mobile-web-app-title][content='wrong tool']"
  end
end
