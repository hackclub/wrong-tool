require "application_system_test_case"
require_relative "../support/sheet_helpers"

class SheetFormattingTest < ApplicationSystemTestCase
  include SheetHelpers

  setup do
    visit root_path
    record_formats
  end

  test "bold, italic and underline toggle from the keyboard and the toolbar" do
    type_into 0, 24, "text", :enter
    click_cell column: 0, row: 24
    page.send_keys [ :control, "b" ], [ :control, "i" ]
    command "underline"

    assert_equal "700", inline_style(entry("A25"), "font-weight")
    assert_equal "italic", inline_style(entry("A25"), "font-style")
    assert_equal "underline", inline_style(entry("A25"), "text-decoration-line")
    assert reported_format["bold"]
    assert reported["canUndo"]

    page.send_keys [ :control, "b" ]
    assert_equal "400", inline_style(entry("A25"), "font-weight")
    assert_not reported_format["bold"]
  end

  test "formats apply across the selected range, empty cells included" do
    select_range "A25:B26"
    command "fillColor", "#ff0000"

    assert_selector ".sheet-entry", count: 4
    assert_equal "rgb(255, 0, 0)", inline_style(entry("B26"), "background")
    select_range "A25:B26"
    command "clearFormat"
    assert_no_selector ".sheet-entry"
  end

  test "formats follow a range selected with Shift and the arrows" do
    click_cell column: 0, row: 24
    page.send_keys [ :shift, :arrow_right ], [ :shift, :arrow_down ]
    command "bold"
    command "italic" # the range is still selected after the first command

    assert_selector ".sheet-entry", count: 4
    assert_equal "italic", inline_style(entry("B26"), "font-style")
    assert_equal "700", inline_style(entry("B26"), "font-weight")
  end

  test "text color, font, size and alignment" do
    type_into 0, 24, "styled", :enter
    click_cell column: 0, row: 24
    command "textColor", "#0000ff"
    command "fontFamily", "Georgia"
    command "fontSize", 18
    command "fontSizeStep", 1
    command "alignH", "center"
    command "alignV", "top"
    command "wrap", "wrap"

    cell = entry("A25")
    assert_equal "rgb(0, 0, 255)", inline_style(cell, "color")
    assert_includes inline_style(cell, "font-family"), "Georgia"
    assert_equal "19px", inline_style(cell, "font-size")
    assert_equal "center", inline_style(cell, "justify-content")
    assert_equal "flex-start", inline_style(cell, "align-items")
    assert_equal "normal", inline_style(cell, "white-space")
    assert_equal 19, reported_format["fontSize"]
    assert_equal "Georgia", reported_format["fontFamily"]
    assert_equal "center", reported_format["alignH"]
  end

  test "the toolbar reads the landing page's own look" do
    click_cell column: 1, row: 2 # the program name, 84px and bold

    assert_equal 84, reported_format["fontSize"]
    assert reported_format["bold"]
    assert_not reported["canUndo"]
  end

  test "landing cells take formats, and lose them again" do
    click_cell column: 1, row: 10
    command "italic"
    assert_equal "italic", inline_style(find("a.hero__cta"), "font-style")

    command "undo"
    assert_equal "", inline_style(find("a.hero__cta"), "font-style")
  end

  test "number formats and decimal places" do
    type_into 0, 24, "1234.5", :enter
    click_cell column: 0, row: 24
    command "numberFormat", "currency"
    assert_entry "A25", "$1,234.50"

    command "decimals", 1
    assert_entry "A25", "$1,234.500"
    command "numberFormat", "percent"
    assert_entry "A25", "123,450.00%"
    command "numberFormat", "scientific"
    assert_entry "A25", "1.23E+03"
    command "numberFormat", "number"
    command "decimals", -1
    assert_entry "A25", "1,234.5"
    command "numberFormat", "date"
    assert_entry "A25", "5/18/1903"
    command "numberFormat", "automatic"
    assert_entry "A25", "1234.5"
    page.send_keys [ :control, :shift, "4" ]
    assert_entry "A25", "$1,234.50"
  end

  test "typed values read as Sheets reads them" do
    type_into 0, 24, "12%", :enter, "$5", :enter, "1,234", :enter, "9/29/2026", :enter, "=DATE(2026, 1, 2)", :enter, "=A25*2", :enter

    assert_entry "A25", "12%"
    assert_entry "A26", "$5.00"
    assert_entry "A27", "1,234"
    assert_entry "A28", "9/29/2026"
    assert_entry "A29", "1/2/2026"
    assert_entry "A30", "0.24"
  end

  test "plain text keeps what's typed" do
    click_cell column: 0, row: 24
    command "numberFormat", "plain"
    page.send_keys "=1+1", :enter

    assert_entry "A25", "=1+1"
  end

  test "undo and redo cover values, formats and deletes" do
    type_into 0, 24, "one", :enter
    click_cell column: 0, row: 24
    command "bold"
    page.send_keys :delete
    assert_entry "A25", ""

    page.send_keys [ :control, "z" ]
    assert_entry "A25", "one"
    command "undo"
    assert_equal "", inline_style(entry("A25"), "font-weight")
    page.send_keys [ :control, "z" ]
    assert_no_selector ".sheet-entry"
    assert_not reported["canUndo"]
    assert reported["canRedo"]

    page.send_keys [ :control, :shift, "z" ]
    assert_entry "A25", "one"
    page.send_keys [ :control, "y" ], [ :control, "y" ]
    assert_entry "A25", ""
    assert_not reported["canRedo"]
  end

  test "Delete clears the whole range" do
    type_into 0, 24, "1", :tab, "2", :enter
    select_range "A25:B25"
    page.send_keys :backspace

    assert_no_selector ".sheet-entry"
  end

  test "copy puts tab-separated values on the clipboard" do
    type_into 0, 24, "a", :tab, "=1+1", :enter
    select_range "A25:B25"

    assert_equal "a\t2", clipboard_event("copy")
  end

  test "pasting tab-separated values from another spreadsheet fills the cells" do
    click_cell column: 0, row: 29
    clipboard_event "paste", "x\t1\n\"two\nlines\"\t=A30&\"!\"\r\n"

    assert_entry "A30", "x"
    assert_entry "B30", "1"
    assert_equal "two\nlines", entry("A31")["data-formula"]
    assert_entry "B31", "x!"
  end

  test "copying and pasting a formula moves its references, and brings its format" do
    type_into 0, 24, "1", :tab, "2", :tab, "=A25+B25", :enter
    click_cell column: 2, row: 24
    command "bold"
    clipboard_event "copy"

    click_cell column: 2, row: 25
    clipboard_event "paste", "3"
    assert_selector "#{entry_selector("C26")}[data-formula='=A26+B26']"
    assert_equal "700", inline_style(entry("C26"), "font-weight")
  end

  test "cut and paste moves cells" do
    type_into 0, 24, "move me", :enter
    click_cell column: 0, row: 24
    command "italic"
    text = clipboard_event("cut")

    click_cell column: 3, row: 29
    clipboard_event "paste", text
    assert_entry "D30", "move me"
    assert_no_selector entry_selector("A25")
    assert_equal "italic", inline_style(entry("D30"), "font-style")
  end

  test "one value pasted over a range fills it" do
    select_range "A25:B26"
    clipboard_event "paste", "7"

    assert_selector ".sheet-entry", exact_text: "7", count: 4
  end

  test "merging keeps the top-left value across the range, and unmerging splits it" do
    type_into 0, 24, "kept", :tab, "dropped", :enter
    select_range "A25:C26"
    command "merge", "all"

    assert_selector ".sheet-entry", count: 1
    assert_selector ".sheet-entry[style*='grid-area: 25 / 1 / span 2 / span 3']", exact_text: "kept"

    click_cell column: 2, row: 25 # inside the merge: selects it
    assert_selection "A25", formula: "kept"

    select_range "A25:C26"
    command "merge", "unmerge"
    assert_selector ".sheet-entry[style*='grid-area: 25 / 1;']", exact_text: "kept"
  end

  test "borders go on the range's edges" do
    select_range "A25:B26"
    command "borders", "outer"

    assert_equal 4, all(".sheet-entry", minimum: 4).count
    assert_match(/^0 -1px .*, -1px 0 /, inline_style(entry("A25"), "box-shadow")) # top and left
    assert_match(/^0 1px .*, 1px 0 /, inline_style(entry("B26"), "box-shadow")) # bottom and right
    select_range "A25:B26"
    command "borders", "none"
    assert_no_selector ".sheet-entry"
  end

  test "notes mark their cell and show on hover" do
    type_into 0, 24, "noted", :enter
    click_cell column: 0, row: 24
    command "comment", "remember this"

    assert_selector ".sheet-noted[data-note='remember this']"
    assert_selector ".sheet-note-marker[style*='grid-area: 25 / 1']"
    entry("A25").hover
    assert_selector ".sheet-note", text: "remember this"
  end

  test "notes work on landing cells too" do
    click_cell column: 1, row: 10
    command "comment", "the button"

    assert_selector "a.hero__cta.sheet-noted"
    assert_selector ".sheet-note-marker[style*='grid-area: 11 / 2 / span 1 / span 2']"
    command "comment", ""
    assert_no_selector ".sheet-note-marker"
  end

  test "links become hyperlinks, with a chip to follow them" do
    type_into 0, 24, "hack club", :enter
    click_cell column: 0, row: 24
    command "insertLink", "hackclub.com"

    assert_selector ".sheet-entry--link", exact_text: "hack club"
    assert_selection "A25", formula: '=HYPERLINK("https://hackclub.com", "hack club")'
    assert_selector ".sheet-link-chip a[href='https://hackclub.com']"
  end

  test "the format painter copies a format onto the next cell clicked" do
    type_into 0, 24, "source", :tab, "target", :enter
    click_cell column: 0, row: 24
    command "bold"
    command "paintFormat"
    assert reported["painting"]

    click_cell column: 1, row: 24
    assert_equal "700", inline_style(entry("B25"), "font-weight")
    assert_not reported["painting"]
  end

  test "functions sum a range into the cell below it" do
    type_into 0, 24, "2", :enter, "3", :enter
    select_range "A25:A26"
    command "insertFunction", "SUM"

    assert_entry "A27", "5"
  end

  test "a function on one cell opens the editor" do
    click_cell column: 0, row: 24
    command "insertFunction", "AVERAGE"

    assert_equal "=AVERAGE(", find(".sheet__editor").value
    page.send_keys "4,6)", :enter
    assert_entry "A25", "5"
  end

  test "rotated text turns inside its cell" do
    type_into 0, 24, "tilt", :enter
    click_cell column: 0, row: 24
    command "rotate", 45

    assert_equal "-45deg", inline_style(find("#{entry_selector("A25")} .sheet-text"), "rotate")
  end

  test "formats persist per tab, and reset this sheet brings the page back" do
    type_into 0, 24, "saved", :enter
    click_cell column: 0, row: 24
    command "bold"
    click_cell column: 1, row: 10
    page.send_keys "over", :enter
    refresh

    assert_equal "700", inline_style(entry("A25"), "font-weight")
    assert_selector ".sheet-shell.hero__cta", exact_text: "over"
    click_on "FAQ"
    assert_no_selector ".sheet-entry"
    click_on "Hero"

    command "clearSheet"
    assert_no_selector ".sheet-entry"
    assert_no_selector ".sheet-shell"
    assert_nil evaluate_script(%(localStorage.getItem("wrong-tool:sheet:hero")))
    command "undo"
    assert_entry "A25", "saved"
  end

  test "commands nobody handles are ignored" do
    click_cell column: 0, row: 24
    command "zoom", 150
    command "doesNotExist"

    assert_no_selector ".sheet-entry"
    assert_selection "A25", formula: ""
  end

  private
    # Fires a clipboard event at the grid, as Ctrl+C / Ctrl+X / Ctrl+V would, and returns
    # what ended up on the clipboard.
    def clipboard_event(type, text = nil)
      execute_script(<<~JS, type, text)
        const data = new DataTransfer()
        if (arguments[1] !== null) data.setData("text/plain", arguments[1])
        const grid = document.querySelector(".sheet__cells")
        grid.focus()
        grid.dispatchEvent(new ClipboardEvent(arguments[0], { clipboardData: data, bubbles: true, cancelable: true }))
        return data.getData("text/plain")
      JS
    end
end
