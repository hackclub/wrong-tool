require "application_system_test_case"

class SheetTabsTest < ApplicationSystemTestCase
  test "tabs switch sections and the back button restores the previous one" do
    visit root_path
    assert_selector "section#hero", visible: true
    assert_selector ".sheet-tab[aria-current=page]", text: "Hero"

    click_on "FAQ"
    assert_equal "#faq", evaluate_script("location.hash")
    assert_selector "section#faq", visible: :all
    assert_no_selector "section#hero"
    assert_selector ".sheet-tab[aria-current=page]", text: "FAQ"

    go_back
    assert_selector "section#hero", visible: true
    assert_selector ".sheet-tab[aria-current=page]", text: "Hero"
  end

  test "opens the section named in the URL" do
    visit "/#faq"
    assert_no_selector "section#hero"
    assert_selector ".sheet-tab[aria-current=page]", text: "FAQ"
  end
end
