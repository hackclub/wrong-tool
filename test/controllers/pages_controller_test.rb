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
end
