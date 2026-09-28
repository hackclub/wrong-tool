require "application_system_test_case"

class CellSelectionTest < ApplicationSystemTestCase
  setup { visit root_path }

  test "starts on the hero's call to action" do
    assert_selection "B11", formula: "=BUILD(anyway)"
    assert_selector ".sheet__column-header--selected", count: 2
    assert_selector ".sheet__row-header--selected", count: 1, text: "11"
  end

  test "clicking a merged cell selects all of it" do
    find(".hero__title").click

    assert_selection "B3", formula: '="Lorem ipsum dolor sit amet, consectetur."'
    assert_selector ".sheet__column-header--selected", count: 10
    assert_selector ".sheet__row-header--selected", count: 5
  end

  test "clicking an empty cell selects just that cell" do
    click_cell column: 5, row: 19 # F20

    assert_selection "F20", formula: ""
  end

  test "arrow keys step off the edge of merged cells" do
    find(".sheet__cells").send_keys(:right) # from B11, which spans B:C
    assert_selection "D11", formula: "=CANCEL()"

    find(".sheet__cells").send_keys(:up, :up) # D9 is inside the subtitle at B9:G9
    assert_selection "B9", formula: "Sed do eiusmod tempor incididunt ut labore."
  end

  test "the #N/A cell shows its note only while selected" do
    assert_no_selector ".hero__cancel-note"

    find(".hero__cancel").click
    assert_selector ".hero__cancel-note", text: '"Cancel" is not a valid function'

    find(".sheet__cells").send_keys(:down)
    assert_no_selector ".hero__cancel-note"
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
