require "application_system_test_case"
require_relative "../support/sheet_helpers"

class SheetEditorTest < ApplicationSystemTestCase
  include SheetHelpers

  setup { visit root_path }

  # Column A is always empty, so it's free to type into.
  test "typing into an empty cell fills it in and Enter moves down" do
    click_cell column: 0, row: 24
    page.send_keys "42", :enter

    assert_entry "A25", "42"
    assert_selection "A26", formula: ""
  end

  test "formulas work out from other cells, and the formula bar shows them" do
    type_into 0, 24, "2", :enter, "3", :enter, "=SUM(A25:A26)*2", :enter

    assert_entry "A27", "10"
    click_cell column: 0, row: 26
    assert_selection "A27", formula: "=SUM(A25:A26)*2"

    click_cell column: 0, row: 24
    page.send_keys "5", :enter
    assert_entry "A27", "16"
  end

  test "formulas can read the landing page" do
    type_into 0, 24, "=UPPER(B3)", :enter

    assert_entry "A25", "WRONG TOOL"
  end

  test "errors show in their cell" do
    type_into 0, 24, "=1/0", :enter, "=A27", :enter, "=A26", :enter

    assert_entry "A25", "#DIV/0!"
    assert_entry "A26", "#REF!" # A26 and A27 read each other
    assert_selector ".sheet-entry--error", count: 3
  end

  test "Escape cancels, and Delete clears" do
    type_into 0, 24, "keep", :enter
    click_cell column: 0, row: 24
    page.send_keys "gone", :escape
    assert_entry "A25", "keep"
    assert_no_selector ".sheet__editor"

    page.send_keys :delete
    assert_no_selector ".sheet-entry"
  end

  test "double-clicking or Enter edits what's there" do
    type_into 0, 24, "=1+1", :enter
    click_cell column: 0, row: 24
    click_cell column: 0, row: 24, type: "dblclick"

    assert_equal "=1+1", find(".sheet__editor").value
    page.send_keys "0", :tab
    assert_entry "A25", "11"
    assert_selection "B25", formula: ""
  end

  test "the formula bar opens the editor" do
    click_cell column: 0, row: 24
    find(".formula-bar__content").click
    page.send_keys "from the bar", :enter

    assert_entry "A25", "from the bar"
  end

  test "the landing page's own cells can be typed over, and come back" do
    click_cell column: 1, row: 10 # the call to action
    page.send_keys "hello", :enter

    assert_selector ".sheet-shell.hero__cta", exact_text: "hello"
    assert_no_selector ".hero__cta:not(.sheet-shell)"
    assert_selection "B12", formula: ""
    click_cell column: 1, row: 10
    assert_selection "B11", formula: "hello"

    page.send_keys :delete
    assert_selector ".sheet-shell.hero__cta", exact_text: ""

    page.send_keys [ :control, "z" ], [ :control, "z" ]
    assert_no_selector ".sheet-shell"
    assert_selector "a.hero__cta", text: "Start building"
    assert_selection "B11", formula: "=START(building)"
  end

  test "Enter edits a landing cell's own formula, and Escape leaves it be" do
    click_cell column: 1, row: 10
    page.send_keys :enter

    assert_equal "=START(building)", find(".sheet__editor").value
    page.send_keys :escape
    assert_no_selector ".sheet-shell"

    # Saving it unchanged keeps the page's own cell.
    page.send_keys :f2, :enter
    assert_no_selector ".sheet-shell"
    assert_selector "a.hero__cta", text: "Start building"
  end

  test "formulas read landing cells that have been typed over" do
    click_cell column: 1, row: 10
    page.send_keys "21", :enter
    type_into 0, 24, "=B11*2", :enter

    assert_entry "A25", "42"
  end

  test "typing over the flap board hides it, and the game keeps out of the way" do
    click_cell column: 8, row: 3
    page.send_keys "board", :enter
    assert_selector ".sheet-shell.flap__board", exact_text: "board"
    assert_no_selector ".flap__board:not(.sheet-shell)"

    type_into 0, 24, "a b", :enter # space no longer flaps
    assert_entry "A25", "a b"
    assert_no_selector ".flap__board--running", visible: :all

    command "clearSheet"
    assert_no_selector ".sheet-shell"
    assert_no_selector ".sheet-entry"
    click_cell column: 0, row: 24
    page.send_keys " "
    assert_selector ".flap__board--running"
  end

  test "landing edits survive a reload and the phone layout" do
    click_cell column: 1, row: 10
    page.send_keys "phone", :enter
    refresh
    assert_selector ".sheet-shell.hero__cta", exact_text: "phone"

    page.current_window.resize_to(390, 844)
    assert_selector ".sheet-shell.hero__cta", exact_text: "phone"
    assert_no_selector ".hero__cta:not(.sheet-shell)"
  ensure
    page.current_window.resize_to(1400, 1400)
  end

  test "space types a space instead of flapping" do
    type_into 0, 24, "a b", :enter

    assert_entry "A25", "a b"
    assert_no_selector ".flap__board--running"
  end

  test "each tab keeps its own entries, across visits" do
    type_into 0, 24, "hero", :enter
    click_on "FAQ"
    assert_no_selector ".sheet-entry"

    type_into 0, 24, "faq", :enter
    visit root_path
    assert_entry "A25", "hero"
    click_on "FAQ"
    assert_entry "A25", "faq"
  end

  test "entries under the page's own cells are kept but not shown" do
    execute_script(%(localStorage.setItem("wrong-tool:entries:hero", JSON.stringify({ B3: "hidden", A25: "=B3" }))))
    refresh

    assert_selector ".sheet-entry", count: 1
    assert_entry "A25", "wrong tool"
  end

  test "entries saved before formatting move over to the new storage" do
    execute_script(%(localStorage.setItem("wrong-tool:entries:hero", JSON.stringify({ A25: "old" }))))
    refresh

    assert_entry "A25", "old"
    assert_nil evaluate_script(%(localStorage.getItem("wrong-tool:entries:hero")))
    assert_equal({ "cells" => { "A25" => { "value" => "old" } } }, JSON.parse(evaluate_script(%(localStorage.getItem("wrong-tool:sheet:hero")))))
  end
end
