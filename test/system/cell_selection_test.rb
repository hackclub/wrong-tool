require "application_system_test_case"

class CellSelectionTest < ApplicationSystemTestCase
  setup { visit root_path }

  test "starts on the hero's call to action" do
    assert_selection "B11", formula: "=START(building)"
    assert_selector ".sheet__column-header--selected", count: 2
    assert_selector ".sheet__row-header--selected", count: 1, text: "11"
  end

  test "clicking a merged cell selects all of it" do
    find(".hero__title").click

    assert_selection "B6", formula: %(="make a game in something that isn't a game engine.")
    assert_selector ".sheet__column-header--selected", count: 7
    assert_selector ".sheet__row-header--selected", count: 2
  end

  test "clicking an empty cell selects just that cell" do
    click_cell column: 0, row: 24 # A25; column A is always empty

    assert_selection "A25", formula: ""
  end

  test "arrow keys step off the edge of merged cells" do
    find(".sheet__cells").send_keys(:right) # from B11, which spans B:C
    assert_selection "D11", formula: ""

    find(".sheet__cells").send_keys(:up) # D10 is inside the subtitle at B9:G10
    assert_selection "B9", formula: "build it in google sheets, figma, email, or whatever else you like. log 10 hours and we'll send you a handheld."
  end

  test "the art under the program name is a cell of its own" do
    click_cell column: 6, row: 3 # G4, beside the name

    assert_selection "B2", formula: %(=IMAGE("screwdriver_driving_a_nail.png"))
  end

  test "switching tabs resets the selection" do
    click_on "FAQ"
    assert_selection "B2", formula: "FAQ"
  end

  private
    # Selenium measures click offsets from the visible part of the (very wide) grid,
    # so dispatch the click at exact coordinates instead.
    def click_cell(column:, row:)
      execute_script(<<~JS, column, row)
        const grid = document.querySelector(".sheet__cells")
        const { left, top } = grid.getBoundingClientRect()
        grid.dispatchEvent(new MouseEvent("click", {
          bubbles: true, clientX: left + arguments[0] * 100 + 50, clientY: top + arguments[1] * 30 + 15
        }))
      JS
    end

    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
