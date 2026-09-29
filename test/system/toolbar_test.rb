require "application_system_test_case"

class ToolbarTest < ApplicationSystemTestCase
  setup do
    visit root_path
    # Record what the toolbar sends, whatever the sheet does with it.
    execute_script <<~JS
      window.commands = []
      addEventListener("toolbar:command", event => commands.push(event.detail), true)
    JS
  end

  test "buttons send their commands and leave the grid focused" do
    click_cell column: 0, row: 24
    toolbar_button("Bold").click
    toolbar_button("Format as currency").click
    toolbar_button("Increase decimal places").click
    toolbar_button("Decrease font size").click

    assert_commands [ "bold", nil ], [ "numberFormat", "currency" ], [ "decimals", 1 ], [ "fontSizeStep", -1 ]
    assert_grid_focused
  end

  test "menus send their choice, and close on Escape and on a click outside" do
    open_menu "More formats"
    assert_selector "#toolbar-menu-number-format", text: "Percent\n10.12%"
    menu_item("Percent").click
    assert_no_selector "#toolbar-menu-number-format"
    assert_selector "[aria-controls=toolbar-menu-number-format][aria-expanded=false]"

    open_menu "Font"
    page.send_keys :escape
    assert_no_selector "#toolbar-menu-font-family"

    open_menu "Horizontal align"
    click_cell column: 0, row: 24
    find("body").click
    assert_no_selector "#toolbar-menu-alignH"

    open_menu "Horizontal align"
    find("#toolbar-menu-alignH [aria-label=Center]").click
    open_menu "Text rotation"
    find("#toolbar-menu-rotate [aria-label='Tilt up']").click
    open_menu "Font"
    menu_item("Georgia").click
    open_menu "Functions"
    find("#toolbar-menu-functions button", text: "AVERAGE").click
    open_menu "Borders"
    find("#toolbar-menu-borders [aria-label='Outer borders']").click
    toolbar_button("Merge cells").click
    open_menu "Select merge type"
    find("#toolbar-menu-merge button", text: "Unmerge").click

    assert_commands [ "numberFormat", "percent" ], [ "alignH", "center" ], [ "rotate", 45 ], [ "fontFamily", "Georgia" ],
      [ "insertFunction", "AVERAGE" ], [ "borders", "outer" ], [ "merge", "all" ], [ "merge", "unmerge" ]
    assert_grid_focused
  end

  test "color palettes pick a color or reset it" do
    open_menu "Text color"
    find("#toolbar-menu-textColor [aria-label='dark red 1']").click
    open_menu "Fill color"
    find("#toolbar-menu-fillColor button", text: "Reset").click

    assert_commands [ "textColor", "#cc0000" ], [ "fillColor", nil ]
  end

  test "menus work from the keyboard" do
    button = toolbar_button("Zoom")
    execute_script "arguments[0].focus()", button
    button.send_keys :enter
    assert_equal "50%", evaluate_script("document.activeElement.textContent.trim()")

    page.send_keys :down, :down, :enter
    assert_commands [ "zoom", 90 ]
    assert_selector "[data-toolbar-target=zoomLabel]", text: "90%"
  end

  test "the font size box takes a size, then hands focus back to the grid" do
    find("#toolbar-font-size").click
    assert_selector "#toolbar-menu-font-size"
    find("#toolbar-font-size").send_keys [ :control, "a" ], "24", :enter

    assert_commands [ "fontSize", 24 ]
    assert_no_selector "#toolbar-menu-font-size"
    assert_grid_focused
  end

  test "links and comments are typed into popovers" do
    open_menu "Insert link"
    find("#toolbar-menu-link input").send_keys "https://hackclub.com", :enter
    open_menu "Add comment"
    find("#toolbar-menu-comment textarea").send_keys "ship it"
    find("#toolbar-menu-comment button", text: "Comment").click

    assert_commands [ "insertLink", "https://hackclub.com" ], [ "comment", "ship it" ]
    assert_grid_focused
  end

  test "the toolbar follows the active cell's format" do
    execute_script <<~JS
      document.querySelector(".spreadsheet").dispatchEvent(new CustomEvent("sheet-editor:format", { bubbles: true, detail: {
        format: { bold: true, fontFamily: "Georgia", fontSize: 24, alignH: "right", textColor: "rgb(204, 0, 0)", zoom: 50 },
        canUndo: true, canRedo: false, painting: true
      } }))
    JS

    assert_selector "[aria-label=Bold][aria-pressed=true]"
    assert_selector "[aria-label=Italic][aria-pressed=false]"
    assert_selector "[aria-label='Paint format'][aria-pressed=true]"
    assert_selector "[data-toolbar-target=fontFamily]", text: "Georgia"
    assert_equal "24", find("#toolbar-font-size").value
    assert_no_selector "[aria-label=Undo][aria-disabled=true]"
    assert_selector "[aria-label=Redo][aria-disabled=true]"
    assert evaluate_script(<<~JS), "the align button shows the right-align icon"
      document.querySelector("[aria-controls=toolbar-menu-alignH] .toolbar__current").innerHTML ===
        document.querySelector("#toolbar-menu-alignH [aria-label=Right] .icon").outerHTML
    JS
    assert_selector "#toolbar-menu-textColor [aria-label='dark red 1'][aria-checked=true]", visible: :all

    toolbar_button("Redo").click
    assert_commands
  end

  test "zoom scales the grid, and clicks and arrow keys still land on the right cell" do
    [ 200, 50 ].each do |zoom|
      open_menu "Zoom"
      menu_item("#{zoom}%").click
      assert_selector "[data-toolbar-target=zoomLabel]", text: "#{zoom}%"
      assert_in_delta zoom / 100.0, evaluate_script("document.querySelector('.sheet__cells').currentCSSZoom")

      # Empty cells: column A at 200%, far off to the bottom right at 50%.
      column, row, keys, moved = zoom == 200 ? [ 0, 12, [ :down, :down ], [ 0, 14 ] ] : [ 20, 50, [ :down, :right ], [ 21, 51 ] ]
      click_at column:, row:, zoom: zoom / 100.0
      assert_selection address(column, row), formula: ""
      assert_selection_over column, row, zoom / 100.0

      page.send_keys(*keys)
      assert_selection address(*moved), formula: ""
      assert_selection_over(*moved, zoom / 100.0)
    end
  end

  test "zoomed in, moving past the edge scrolls the selection into view" do
    open_menu "Zoom"
    menu_item("200%").click
    click_at column: 0, row: 12, zoom: 2
    30.times { page.send_keys :down }

    assert_selection "A43", formula: ""
    assert evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(".sheet__selection").getBoundingClientRect()
        const view = document.querySelector(".sheet-viewport").getBoundingClientRect()
        return box.top >= view.top && box.bottom <= view.bottom + 1
      })()
    JS
  end

  test "zoom is remembered and can be set from the View menu" do
    open_menu "Zoom"
    menu_item("150%").click
    visit root_path
    assert_selector "[data-toolbar-target=zoomLabel]", text: "150%"

    execute_script <<~JS
      document.querySelector(".menu-bar").dispatchEvent(new CustomEvent("menu-bar:command", { bubbles: true, detail: { command: "zoom", value: 75 } }))
    JS
    assert_selector "[data-toolbar-target=zoomLabel]", text: "75%"
    assert_in_delta 0.75, evaluate_script("document.querySelector('.sheet__cells').currentCSSZoom")
  end

  test "print, filter, and hiding the menus" do
    execute_script "window.printed = 0; window.print = () => printed++"
    toolbar_button("Print").click
    assert_equal 1, evaluate_script("printed")

    click_cell column: 0, row: 24
    toolbar_button("Create a filter").click
    assert_selector ".toolbar-filter"
    assert_selector ".sheet__column-header.toolbar-filter__header", count: 1, text: "A"
    assert_selector "[aria-label='Create a filter'][aria-pressed=true]"
    toolbar_button("Create a filter").click
    assert_no_selector ".toolbar-filter"

    toolbar_button("Hide the menus").click
    assert_no_selector ".app-bar"
    toolbar_button("Show the menus").click
    assert_selector ".app-bar"
    assert_selector "[aria-label='Insert chart'][aria-disabled=true]"
    assert_commands
  end

  test "the menus search finds toolbar actions" do
    find("[aria-label='Search the menus']").send_keys "stri"
    assert_selector "#toolbar-menu-search [role=option]", text: "Strikethrough"
    find("[aria-label='Search the menus']").send_keys :enter

    assert_commands [ "strikethrough", nil ]
    assert_no_selector "#toolbar-menu-search"
  end

  test "the menus search lists menu bar items by their label, without shortcuts" do
    find("[aria-label='Search the menus']").send_keys "copy"
    assert_selector "#toolbar-menu-search [role=option]", exact_text: "Edit: Copy"
    assert_no_selector "#toolbar-menu-search [role=option]", text: /Ctrl|⌘/
  end

  test "tooltips name the button" do
    toolbar_button("Bold").hover
    assert_selector ".toolbar-tooltip", text: /Bold \((Ctrl\+|⌘)B\)/
  end

  # With the sheet editor carrying the commands out.
  test "bold and fill color format the selected cell" do
    click_cell column: 0, row: 24
    page.send_keys "hi", :enter
    click_cell column: 0, row: 24
    toolbar_button("Bold").click
    open_menu "Fill color"
    find("#toolbar-menu-fillColor [aria-label='light yellow 3']").click

    entry = find(".sheet-entry", text: "hi")
    assert_equal "700", entry.style("font-weight")["font-weight"]
    assert_match(/rgba?\(255, 242, 204/, entry.style("background-color")["background-color"])
    assert_selector "[aria-label=Bold][aria-pressed=true]"
    assert_no_selector "[aria-label=Undo][aria-disabled=true]"

    toolbar_button("Undo").click
    assert_selector "[aria-label=Bold][aria-pressed=true]"
    toolbar_button("Undo").click
    assert_selector "[aria-label=Bold][aria-pressed=false]"
  end

  private
    def toolbar_button(label)
      find(".toolbar [aria-label='#{label}']")
    end

    def open_menu(label)
      toolbar_button(label).click
      assert_selector ".toolbar [aria-label='#{label}'][aria-expanded=true]"
    end

    def menu_item(label)
      find(".toolbar-menu:not([hidden]) .toolbar-menu__label", exact_text: label)
    end

    def assert_commands(*expected)
      assert_equal expected, evaluate_script("commands").map { |detail| [ detail["command"], detail["value"] ] }
    end

    def assert_grid_focused
      assert evaluate_script("document.activeElement.matches('.sheet__cells')"), "the grid should have focus"
    end

    def address(column, row)
      "#{("A".."Z").to_a[column]}#{row + 1}"
    end

    # A real mouse click on the middle of a cell, at the zoomed size.
    def click_at(column:, row:, zoom:)
      x, y = evaluate_script(<<~JS, column, row, zoom)
        (() => {
          const { left, top } = document.querySelector(".sheet__cells").getBoundingClientRect()
          return [ left + (arguments[0] * 100 + 50) * arguments[2], top + (arguments[1] * 30 + 15) * arguments[2] ]
        })()
      JS
      page.driver.browser.action.move_to_location(x.round, y.round).click.perform
    end

    def assert_selection_over(column, row, zoom)
      left, top = evaluate_script(<<~JS)
        (() => {
          const grid = document.querySelector(".sheet__cells").getBoundingClientRect()
          const box = document.querySelector(".sheet__selection").getBoundingClientRect()
          return [ box.left - grid.left, box.top - grid.top ]
        })()
      JS
      assert_in_delta column * 100 * zoom, left, 3 * zoom
      assert_in_delta row * 30 * zoom, top, 3 * zoom
    end
end
