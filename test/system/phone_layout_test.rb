require "application_system_test_case"

class PhoneLayoutTest < ApplicationSystemTestCase
  # Headless Chrome won't size a window below 500px, so emulate the phone instead.
  setup do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit root_path
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "keeps the Start pill and drops the desktop-only chrome" do
    assert_selector ".app-bar__build-button", exact_text: "Start"
    assert_no_selector ".toolbar"
    assert_no_selector ".menu-bar"
  end

  test "re-lays the hero into columns A to D, starting on the call to action" do
    assert_selection "A9", formula: "=START(building)"
    assert_no_selector ".hero__art"

    find(".hero__name").click
    assert_selection "A2", formula: '=YSWS("wrong tool")'
  end

  test "every other sheet starts on A1 and sits in columns A to D" do
    %w[How\ it\ works Ideas FAQ].each do |name|
      click_on name
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: "A1"
    end
  end

  test "sheets re-lay their tables into columns A to D" do
    click_on "How it works"
    all(".how-it-works__detail--item").first.click
    assert_selection "B6", formula: "Pick one tool that isn't a game engine: google sheets, figma, slides, forms, css, your inbox. The whole game gets built inside it."

    click_on "Ideas"
    find(".ideas__reel--platform").click
    assert_selection "C7", formula: '="figma"'
  end

  test "the FAQ stacks each answer under its question" do
    click_on "FAQ"
    all(".faq__answer--item").first.click
    assert_selection "A6", formula: "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
    all(".faq__question--item")[1].click
    assert_selection "A10", formula: "Sit amet consectetur?"
  end

  test "leaves flap to the desktop" do
    assert_no_selector ".flap__board"
  end

  test "the footer follows each sheet's content" do
    { "Hero" => "A22", "How it works" => "A33", "Ideas" => "A24", "FAQ" => "A41" }.each do |name, address|
      click_on name
      find(".sheet__section:not([hidden]) .sheet-footer__text").click
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
    end
  end

  private
    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
