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
    assert_no_link "Open the real sheet"
  end

  test "re-lays the hero into columns A to D, starting on the call to action" do
    assert_selection "A9", formula: "=START(building)"
    assert_no_selector ".hero__art"

    find(".hero__name").click
    assert_selection "A2", formula: '=YSWS("wrong tool")'

    find(".hero__pick-one").click
    assert_selection "A19", formula: "=CHOOSE(1, 2)"
  end

  private
    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
