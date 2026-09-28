require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "home renders the spreadsheet with every section tab" do
    get root_path

    assert_response :success
    assert_select ".sheet-tab", 7
    assert_select ".sheet-tab[aria-current=page]", text: /Hero/
  end
end
