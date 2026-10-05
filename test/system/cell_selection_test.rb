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
    assert_selection "D11", formula: %(=DATE(2026,10,6) & " → " & DATE(2026,10,20))

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

  # Below the hero's content (it ends at row 22) and in column A, everything is empty.
  test "Shift+arrows grow and shrink a range from the active cell" do
    click_cell column: 0, row: 39 # A40
    grid.send_keys [ :shift, :down ], [ :shift, :down ], [ :shift, :right ]

    assert_range "A40:B42"
    assert_equal "", find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    assert_selector ".sheet__column-header--selected", count: 2
    assert_selector ".sheet__row-header--selected", count: 3
    assert_selector ".sheet__range:not(.sheet__range--single)"

    grid.send_keys [ :shift, :up ], [ :shift, :left ]
    assert_range "A40:A41"
    grid.send_keys [ :shift, :up ], [ :shift, :up ]
    assert_range "A39:A40"

    grid.send_keys :right # a plain arrow collapses the range and moves from the active cell
    assert_selection "B40", formula: ""
    assert_selector ".sheet__range.sheet__range--single"
  end

  test "the select event carries the range" do
    execute_script(<<~JS)
      window.selections = []
      document.addEventListener("cell-selection:select", ({ detail }) => window.selections.push(detail.range))
    JS
    click_cell column: 0, row: 39
    grid.send_keys [ :shift, :right ], [ :shift, :down ]

    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "A40:B41"
    assert_equal({ "column" => 0, "row" => 39, "width" => 2, "height" => 2 }, evaluate_script("window.selections.at(-1)"))
    assert_equal({ "column" => 0, "row" => 39, "width" => 1, "height" => 1 }, evaluate_script("window.selections[0]"))
  end

  test "Shift+click and dragging select ranges" do
    click_cell column: 0, row: 39
    click_cell column: 2, row: 44, shift: true
    assert_range "A40:C45"

    mouse "mousedown", column: 3, row: 49 # D50
    mouse "mousemove", column: 1, row: 51, target: "window"
    mouse "mouseup", column: 1, row: 51, target: "window"
    assert_range "B50:D52"
    assert_selector ".sheet__selection.sheet__selection--in-range"

    mouse "mousemove", column: 5, row: 60, target: "window" # the drag is over
    assert_range "B50:D52"
  end

  test "ranges grow to cover merged cells" do
    click_cell column: 0, row: 5 # A6, beside the title at B6:H7
    grid.send_keys [ :shift, :right ]

    assert_range "A6:H7"
  end

  test "the headers select whole columns and rows, and the corner selects everything" do
    header ".sheet__column-header", 1
    assert_range "B:B"
    assert_selector ".sheet__column-header--full", count: 1, text: "B"
    assert_selector ".sheet__row-header--selected", count: all(".sheet__row-header").size

    header ".sheet__column-header", 3, shift: true
    assert_range "B:D"
    assert_selector ".sheet__column-header--full", count: 3

    header ".sheet__row-header", 4
    assert_range "5:5"
    assert_selector ".sheet__row-header--full", count: 1, text: "5"
    assert_selector ".sheet__column-header--selected", count: 26

    header ".sheet__corner"
    rows = all(".sheet__row-header").size
    assert_range "A1:Z#{rows}"

    grid.send_keys :down
    assert_selection "A2", formula: ""
  end

  test "Ctrl+A selects everything" do
    grid.send_keys [ :control, "a" ]
    assert_range "A1:Z#{all(".sheet__row-header").size}"
  end

  test "Ctrl+arrows jump to the edge of the data, and Ctrl+Shift+arrows select up to it" do
    click_cell column: 0, row: 39
    page.send_keys "1", :enter, "2", :enter, "3", :enter # A40:A42, then A43 is selected
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "A43"
    grid.send_keys :down, :down # A45

    grid.send_keys [ :control, :up ]
    assert_selection "A42", formula: "3"
    grid.send_keys [ :control, :up ]
    assert_selection "A40", formula: "1"
    grid.send_keys [ :control, :up ]
    assert_selection "A1", formula: ""

    click_cell column: 0, row: 39
    grid.send_keys [ :control, :shift, :down ]
    assert_range "A40:A42"

    click_cell column: 0, row: 24 # A25: row 25 is empty right across
    grid.send_keys [ :control, :right ]
    assert_selection "Z25", formula: ""
    grid.send_keys :home
    assert_selection "A25", formula: ""
  end

  test "the name box goes to an address or a range" do
    find(".formula-bar__name-box").click
    assert_selector ".formula-bar__name-input"
    assert_no_selector ".sheet__editor" # it's not the formula bar
    find(".formula-bar__name-input").send_keys "a5", :enter
    assert_selection "A5", formula: ""
    assert_no_selector ".formula-bar__name-input"

    find(".formula-bar__name-box").click
    find(".formula-bar__name-input").send_keys "A40:C45", :enter
    assert_range "A40:C45"

    find(".formula-bar__name-box").click
    find(".formula-bar__name-input").send_keys "D12", :escape
    assert_range "A40:C45"
    grid.send_keys :right # the grid has the keys back
    assert_selection "B40", formula: ""
  end

  test "an address that isn't one leaves the name box open" do
    find(".formula-bar__name-box").click
    find(".formula-bar__name-input").send_keys "nope", :enter

    assert_selector ".formula-bar__name-input"
    assert_selector "[data-cell-selection-target=nameBox]", visible: :hidden, exact_text: "B11"
  end

  test "the goTo and selectAll commands move the selection, and it ignores the others" do
    command "goTo", "b12"
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "B12"
    command "bold"
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "B12"
    command "selectAll"
    assert_range "A1:Z#{all(".sheet__row-header").size}"
  end

  test "going past the last row adds rows to reach it" do
    command "goTo", "A300"
    assert_selection "A300", formula: ""
    assert_selector ".sheet__row-header", text: "300"
  end

  private
    def grid
      find(".sheet__cells")
    end

    def assert_range(name)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: name
    end

    def command(command, value = nil)
      execute_script(<<~JS, command, value)
        document.querySelector(".menu-bar").dispatchEvent(new CustomEvent("menu-bar:command", {
          bubbles: true, detail: { command: arguments[0], value: arguments[1] }
        }))
      JS
    end

    # Dispatched at exact coordinates, like click_cell. Moves and releases go to the window, as when the mouse leaves the cell.
    def mouse(type, column:, row:, target: "grid", shift: false)
      execute_script(<<~JS, type, column, row, target, shift)
        const grid = document.querySelector(".sheet__cells")
        const { left, top } = grid.getBoundingClientRect()
        const target = arguments[3] === "window" ? window : grid
        target.dispatchEvent(new MouseEvent(arguments[0], {
          bubbles: true, button: 0, buttons: arguments[0] === "mouseup" ? 0 : 1, shiftKey: arguments[4],
          clientX: left + arguments[1] * 100 + 50, clientY: top + arguments[2] * 30 + 15
        }))
      JS
    end

    def click_cell(column:, row:, type: "click", shift: false)
      return super(column:, row:, type:) unless shift

      mouse "mousedown", column:, row:, shift: true
      mouse "mouseup", column:, row:, target: "window"
    end

    def header(selector, index = 0, shift: false)
      execute_script(<<~JS, selector, index, shift)
        const header = document.querySelectorAll(arguments[0])[arguments[1]]
        header.dispatchEvent(new MouseEvent("mousedown", { bubbles: true, button: 0, buttons: 1, shiftKey: arguments[2] }))
        window.dispatchEvent(new MouseEvent("mouseup", { bubbles: true, button: 0 }))
      JS
    end
end
