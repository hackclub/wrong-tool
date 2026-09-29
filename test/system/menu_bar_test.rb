require "application_system_test_case"

class MenuBarTest < ApplicationSystemTestCase
  setup do
    visit root_path
    execute_script(<<~JS)
      window.menuCommands = []
      document.addEventListener("menu-bar:command", ({ detail }) => window.menuCommands.push(detail))
    JS
  end

  test "a click opens a menu, hovering moves between menus, and Escape or a click outside closes it" do
    open_menu "File"
    assert_selector ".menu-bar__dropdown[aria-label=File]"
    assert_selector ".menu-bar__item[aria-expanded=true]", exact_text: "File"

    find(".menu-bar__item", exact_text: "Edit").hover
    assert_selector ".menu-bar__dropdown[aria-label=Edit]"
    assert_no_selector ".menu-bar__dropdown[aria-label=File]"

    page.send_keys :escape
    assert_no_selector ".menu-bar__dropdown"

    find(".menu-bar__item", exact_text: "Edit").hover # nothing's open, so hovering doesn't open one
    assert_no_selector ".menu-bar__dropdown"

    open_menu "View"
    find(".formula-bar__fx").click
    assert_no_selector ".menu-bar__dropdown"

    open_menu "View"
    find(".menu-bar__item", exact_text: "View").click
    assert_no_selector ".menu-bar__dropdown"
  end

  test "items send their command, and submenus open on hover" do
    choose "Format", "Text", "Bold"
    assert_equal "bold", commands.last["command"]
    assert_no_selector ".menu-bar__dropdown"

    choose "Format", "Number", "Percent"
    assert_equal({ "command" => "numberFormat", "value" => "percent" }, commands.last)

    choose "View", "Zoom", "150%"
    assert_equal({ "command" => "zoom", "value" => 150 }, commands.last)

    choose "Insert", "Function", "AVERAGE"
    assert_equal({ "command" => "insertFunction", "value" => "AVERAGE" }, commands.last)

    choose "Format", "Rotation", "Tilt up"
    assert_equal({ "command" => "rotate", "value" => 45 }, commands.last)

    choose "Edit", "Delete", "Values"
    assert_equal "delete", commands.last["command"]

    choose "File", "Reset this sheet"
    assert_equal "clearSheet", commands.last["command"]
  end

  test "items show their shortcuts, and number formats show an example" do
    open_menu "Edit"
    assert_selector ".menu-bar__entry", text: /Cut\s*(Ctrl\+X|⌘X)/

    open_menu "Format"
    entry("Number").hover
    assert_selector ".menu-bar__entry", text: /Currency\s*\$1,000.12/
  end

  test "Edit > Select all selects the whole sheet, and the grid keeps the keys" do
    choose "Edit", "Select all"
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "A1:Z#{all(".sheet__row-header").size}"

    find(".sheet__cells").send_keys :down
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "A2"
  end

  test "there's no making new sheets: those items are greyed out and do nothing" do
    tabs = all(".sheet-tab").size
    open_menu "File"
    %w[New Import Make\ a\ copy].each do |label|
      assert_selector ".menu-bar__entry[aria-disabled=true]", text: label
    end
    entry("New").click
    assert_selector ".menu-bar__dropdown[aria-label=File]" # stays open, as in Sheets
    assert_no_selector ".menu-bar__dropdown[aria-label=New]"

    open_menu "Insert"
    entry("Sheet").click
    assert_empty commands
    assert_equal tabs, all(".sheet-tab").size
  end

  test "undo and redo follow the sheet editor" do
    open_menu "Edit"
    assert_selector ".menu-bar__entry[data-command=undo][aria-disabled=true]"

    execute_script(<<~JS)
      window.dispatchEvent(new CustomEvent("sheet-editor:format", { detail: { format: {}, canUndo: true, canRedo: false } }))
    JS
    assert_selector ".menu-bar__entry[data-command=undo]:not([aria-disabled])"
    assert_selector ".menu-bar__entry[data-command=redo][aria-disabled=true]"

    entry("Undo").click
    assert_equal "undo", commands.last["command"]
  end

  # With the sheet editor on the other end of the commands.
  test "Edit > Undo undoes typing" do
    click_cell column: 0, row: 24 # A25
    page.send_keys "42", :enter
    assert_selector ".sheet-entry", exact_text: "42"

    choose "Edit", "Undo"
    assert_no_selector ".sheet-entry", exact_text: "42"
    open_menu "Edit"
    assert_selector ".menu-bar__entry[data-command=redo]:not([aria-disabled])"
  end

  test "File > Download > CSV saves the tab as it's shown" do
    execute_script(<<~JS)
      URL.createObjectURL = blob => { window.download = { blob }; return "blob:download" }
      HTMLAnchorElement.prototype.click = function () { if (this.download) window.download.name = this.download }
    JS
    click_cell column: 0, row: 24
    page.send_keys "hello, sheet", :enter

    choose "File", "Download", "Comma separated values (.csv)"
    assert_equal "wrong tool - Hero.csv", evaluate_script("window.download.name")

    rows = evaluate_async_script("window.download.blob.text().then(arguments[0])").split("\r\n")
    assert_equal "wrong tool", rows[2].split(",")[1] # B3, the program's name
    assert_equal "Start building →", rows[10].split(",")[1] # B11
    assert_match(/\A"hello, sheet",*\z/, rows[24]) # A25, quoted for its comma
  end

  test "File > Print prints" do
    execute_script("window.print = () => window.printed = true")
    choose "File", "Print"
    assert evaluate_script("window.printed")
  end

  test "View > Show > Gridlines toggles the grid's lines" do
    choose "View", "Show", "Gridlines"
    assert_selector ".sheet__cells.sheet__cells--no-gridlines"
    open_menu "View"
    entry("Show").hover
    assert_selector ".menu-bar__entry[aria-checked=false]", text: "Gridlines"
    page.send_keys :escape, :escape

    choose "View", "Show", "Gridlines"
    assert_no_selector ".sheet__cells--no-gridlines"
  end

  test "Help > Keyboard shortcuts, or Ctrl+/, opens the shortcuts" do
    choose "Help", "Keyboard shortcuts"
    assert_selector "dialog.menu-dialog--shortcuts[open]", text: "Keyboard shortcuts"
    find(".menu-dialog__search").send_keys "bold"
    assert_selector ".menu-dialog__shortcut", count: 1, text: "Bold"

    find(".menu-dialog__close").click
    assert_no_selector "dialog[open]"

    find(".sheet__cells").send_keys [ :control, "/" ]
    assert_selector "dialog.menu-dialog--shortcuts[open]"
    page.send_keys :escape
    assert_no_selector "dialog[open]"
  end

  test "Insert > Link asks for the link, then sends it" do
    choose "Insert", "Link"
    assert_selector "dialog[open]", text: "Link"
    find(".menu-dialog__input").send_keys "https://hackclub.com", :enter

    assert_no_selector "dialog[open]"
    assert_equal({ "command" => "insertLink", "value" => "https://hackclub.com" }, commands.last)
  end

  test "Ship leads to the program's sheets and pages" do
    choose "Ship", "How it works"
    assert_selector ".sheet-tab[aria-current=page]", text: "How it works"
    assert_selector "#how-it-works:not([hidden])"

    open_menu "Ship"
    assert_selector "a.menu-bar__entry[href='https://hackatime.hackclub.com/'][target=_blank]"
  end

  test "the keyboard moves through the menus" do
    open_menu "Format"
    page.send_keys :down
    assert_equal "Number", evaluate_script("document.activeElement.querySelector('.menu-bar__label').textContent")
    page.send_keys :right
    assert_selector ".menu-bar__dropdown[aria-label=Number]"
    assert_equal "Automatic", evaluate_script("document.activeElement.querySelector('.menu-bar__label').textContent")
    page.send_keys :down, :enter
    assert_equal({ "command" => "numberFormat", "value" => "plain" }, commands.last)

    open_menu "Format"
    page.send_keys :right
    assert_selector ".menu-bar__dropdown[aria-label=Data]"
  end

  test "the document's name is renamed in place, and the browser tab follows" do
    title = find(".app-bar__title")
    title.click
    title.send_keys [ :command, "a" ], [ :control, "a" ], "flappy sheets", :enter
    assert_equal "flappy sheets", page.title

    visit root_path
    assert_equal "flappy sheets", find(".app-bar__title").value
    assert_equal "flappy sheets", page.title

    find(".app-bar__title").click
    find(".app-bar__title").send_keys "!!", :escape
    assert_equal "flappy sheets", find(".app-bar__title").value
  end

  test "File > Rename selects the name" do
    choose "File", "Rename"
    assert_equal "app-bar__title", evaluate_script("document.activeElement.className")
  end

  test "the star toggles, and stays" do
    find(".app-bar__star").click
    assert_selector ".app-bar__star[aria-pressed=true]"
    visit root_path
    assert_selector ".app-bar__star[aria-pressed=true]"
    find(".app-bar__star").click
    assert_selector ".app-bar__star[aria-pressed=false]"
  end

  private
    def commands
      evaluate_script("window.menuCommands")
    end

    def open_menu(name)
      find(".menu-bar__item", exact_text: name).click
      assert_selector ".menu-bar__dropdown[aria-label='#{name}']"
    end

    # Opens a menu, hovers down through its submenus and clicks the last item.
    def choose(menu, *path)
      open_menu menu
      scope = find(".menu-bar__dropdown[aria-label='#{menu}']")
      path.each_with_index do |label, index|
        item = entry(label, scope)
        if index == path.size - 1
          item.click
        else
          item.hover
          scope = find(".menu-bar__dropdown[aria-label='#{label}']")
        end
      end
    end

    def entry(label, scope = page)
      scope.find(".menu-bar__label", exact_text: label, match: :first).ancestor(".menu-bar__entry")
    end
end
