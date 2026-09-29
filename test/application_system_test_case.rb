require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  private
    # Selenium measures click offsets from the visible part of the (very wide) grid,
    # so dispatch the click at exact coordinates instead.
    def click_cell(column:, row:, type: "click")
      execute_script(<<~JS, column, row, type)
        const grid = document.querySelector(".sheet__cells")
        const { left, top } = grid.getBoundingClientRect()
        grid.dispatchEvent(new MouseEvent(arguments[2], {
          bubbles: true, clientX: left + arguments[0] * 100 + 50, clientY: top + arguments[1] * 30 + 15
        }))
      JS
    end

    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
