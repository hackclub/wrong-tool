require "application_system_test_case"

class ShopTest < ApplicationSystemTestCase
  setup do
    mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS", first_name: "Orpheus")
    visit onboarding_path
    execute_script(<<~JS)
      const form = document.createElement("form")
      form.method = "post"
      form.action = "/auth/hackclub"
      document.body.append(form)
      form.submit()
    JS
    assert_current_path onboarding_path
    visit shop_path
  end

  test "browsing the shelf: a tap or the arrow keys move the selection, and Clippy says a line about each tile" do
    assert_selector ".shop__tile[data-selected]", count: 1
    assert_selector "#shop-miyoo[data-yours][data-selected]"
    assert_selector ".formula-bar__name", exact_text: "D4"
    assert_selector ".shop__say", text: "link hackatime on your sheet", wait: 5
    assert_selector ".shop__choice", text: "pick this one", count: 0
    assert_selector ".shop__choice", text: "colour: gray"
    assert_selector ".shop__choice", text: "64GB"
    assert_selector ".shop__choice", text: "another seller, to save on customs"

    find("#shop-rg35xx .shop__tile-button").click
    assert_selector "#shop-rg35xx[data-selected]"
    assert_no_selector "#shop-miyoo[data-selected]"
    assert_selector "#shop-miyoo[data-yours]"
    assert_selector ".formula-bar__name", exact_text: "A4"
    assert_selector ".formula-bar__content", text: '=HANDHELD("rg35xx") → 10 hrs'
    assert_selector ".shop__say", text: "RG35XX Pro: 10 hours. you've logged 0.", wait: 5
    assert_selector "[data-shop-target=customizeName]", exact_text: "RG35XX Pro"
    assert_selector ".shop__choice", text: "pick this one"

    find(".shop").send_keys(:right, :right)
    assert_selector "#shop-rg28xx[data-selected]"
    assert_selector ".formula-bar__name", exact_text: "H4" # past the column of empty cells after the prizes
    find(".shop").send_keys(:right)
    assert_selector "#shop-v90s[data-selected]"
    assert_selector ".formula-bar__name", exact_text: "K4"
    assert_selector ".shop__column-header[data-selected]", count: 3, text: /K|L|M/
  end

  test "answering Clippy with the keys: a colour on your pick saves as you choose it" do
    assert_selector ".shop__say:not([data-typing])", text: "link hackatime", wait: 5 # Enter while he's typing only hurries him
    find(".shop").send_keys(:down, :down) # about the Mini Plus, then colour
    assert_selector ".shop__choice[data-marked]", text: "colour: gray"
    find(".shop").send_keys(:enter)
    assert_selector ".shop__choice", text: "Purple"
    assert_selector ".shop__choice", text: "back"
    find(".shop__choice", text: "Purple").click

    assert_selector ".shop__say", text: "purple. saved.", wait: 5
    assert_selector ".shop__swatch[aria-pressed=true][data-color=purple]"
    assert_selector ".shop__variant", exact_text: "Purple"
    assert_selector ".formula-bar__content", text: '=IMPORTRANGE("lomiyoo.com", "Colour!Purple")'
    assert_equal "purple", projects(:orpheus).reload.prize_color

    # An extra, from the Customize panel, as Miyoo's store sells it: without a card, which takes nothing off a prize.
    find(".shop__chip", text: "No Card").click
    assert_selector ".shop__say", text: "no Card. that makes it 10 hours. saved.", wait: 5
    assert_selector "#shop-miyoo .shop__tile-cost", exact_text: "10 hrs"
    assert_equal({ "storage" => "none" }, projects(:orpheus).reload.prize_options) # every option, as the counter sends them
  end

  test "making another tile your pick, as you've set it up" do
    assert_selector ".shop__say", text: "link hackatime", wait: 5
    find("#shop-rg35xxsp .shop__tile-button").click
    assert_selector ".shop__say", text: "RG35XX SP: 12 hours", wait: 5
    find(".shop__swatch[data-color=green]").click
    assert_selector ".shop__say", text: "green transparent. pick it and it comes like that.", wait: 5
    assert_equal "miyoo", projects(:orpheus).reload.prize

    find(".shop__choice", text: "pick this one").click
    assert_selector ".shop__say", text: "RG35XX SP in green transparent. 12 hours to go.", wait: 5
    assert_selector "#shop-rg35xxsp[data-yours][data-selected]"
    assert_no_selector "#shop-miyoo[data-yours]"
    assert_selector ".formula-bar__content", text: '=PICK("rg35xxsp", "green") → 0 of 12 hrs'
    assert_selector ".sheet-tabs__sum", exact_text: "RG35XX SP · 12 hrs to go"
    assert_no_selector ".shop__choice", text: "pick this one"
    assert_equal [ "rg35xxsp", "green" ], projects(:orpheus).reload.values_at(:prize, :prize_color)
  end

  test "the shelf shows three whole tiles at a time, with a dot a tile, and scrolls on by two" do
    assert_selector ".shop__shelf-more", text: "10 more"
    assert_selector ".shop__dot[data-on]", count: 3
    assert_selector "[data-shop-target=range]", exact_text: "A4:L10"
    assert_no_selector ".shop__shelf-arrow", visible: true
    find(".shop__shelf-more").click
    assert_selector "[data-shop-target=range]", exact_text: "H4:S10", wait: 5
    assert_selector ".shop__dot[data-on]", count: 4
    assert_selector ".shop__shelf-arrow", visible: true
    assert_selector ".shop__shelf-more", text: "7 more"
  end

  test "asking for the same console from another seller, to save on customs: a link in, for an admin to check" do
    assert_selector ".shop__say:not([data-typing])", wait: 5
    assert_selector "[data-shop-target=seller]", exact_text: "Miyoo's store"
    assert_selector ".shop__choice", text: "get it from another seller", count: 0
    find(".shop__choice", text: "another seller, to save on customs").click
    assert_selector ".shop__say", text: "paste a link to the Mini Plus at a seller nearer you, so it gets to you without customs", wait: 5
    assert_selector ".shop__ask", visible: true
    assert_selector ".shop__choice", visible: true, count: 1, text: "back"

    # Where it comes from already isn't another seller.
    fill_in "link to the listing", with: "https://lomiyoo.com/products/miyoo-mini-plus"
    click_on "send"
    assert_selector ".shop__say", text: "that is Miyoo's store, where it comes from already", wait: 5
    assert_empty projects(:orpheus).seller_requests

    fill_in "link to the listing", with: "https://www.aliexpress.com/item/miyoo-mini-plus.html"
    click_on "send"
    assert_selector ".shop__say", text: "got it. someone will check the link and let you know on slack.", wait: 5
    assert_no_selector ".shop__ask", visible: true
    assert_selector "[data-shop-target=seller][href='https://www.aliexpress.com/item/miyoo-mini-plus.html']", exact_text: "aliexpress.com · in review"
    assert_selector ".shop__choice", text: "another seller: in review"
    assert_selector ".formula-bar__content", text: '=REQUEST(seller, "Mini Plus") → in review'
    assert_equal [ "miyoo", "https://www.aliexpress.com/item/miyoo-mini-plus.html", "pending" ],
                 projects(:orpheus).seller_requests.sole.values_at(:prize, :url, :status)
    find("#shop-rg35xx .shop__tile-button").click
    assert_selector "[data-shop-target=seller]", exact_text: "Anbernic's store"

    # Still there after a reload, from the server.
    visit shop_path
    assert_selector "[data-shop-target=seller]", exact_text: "aliexpress.com · in review"
  end

  test "spending approved hours like money: Clippy says what it costs first, then it's in the queue, and the rest's still to spend" do
    projects(:orpheus).ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, built in Sheets.",
                                     repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours: 20,
                                     screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
                      .decide!("approved", by: users(:ana))
    visit shop_path
    assert_selector ".shop__say", text: "20 hours to spend. that covers the Mini Plus in gray, so it's yours to buy.", wait: 5
    assert_selector "#shop-miyoo[data-state=ready] .shop__tile-tag", exact_text: "ready"

    find(".shop__choice", text: "ship it to me").click
    assert_selector ".shop__say", text: "this isn't checkout. it's 10 of your 20 approved hours on the Mini Plus in gray, from Miyoo's store.", wait: 5
    assert_empty projects(:orpheus).orders
    find(".shop__choice", text: "yes, ship it to me").click

    assert_selector ".shop__say", text: "Mini Plus is bought. someone will order it soon. 10 hours left to spend.", wait: 5
    assert_selector "#shop-miyoo[data-state=shipping] .shop__tile-tag", exact_text: "in the queue"
    assert_selector ".shop__stat--ship .shop__stat-value", exact_text: "10 hrs"
    assert_selector "#shop-rg35xx[data-state=ready]"
    assert_selector "#shop-rg35xxsp[data-state=locked]", visible: :all

    # And something that isn't the pick, with the 10 left.
    find("#shop-rg28xx .shop__tile-button").click
    find(".shop__swatch[data-color=black]").click
    find(".shop__choice", text: "ship it to me").click
    assert_selector ".shop__say", text: "it's 8 of your 10 approved hours on the RG28XX in black transparent, from Anbernic's store.", wait: 5
    find(".shop__choice", text: "yes, ship it to me").click
    assert_selector ".shop__say", text: "RG28XX is bought. someone will order it soon. 2 hours left to spend.", wait: 5
    assert_selector "#shop-rg28xx[data-state=shipping]"
    assert_equal [ [ "miyoo", "grey", 10 ], [ "rg28xx", "black", 8 ] ],
                 projects(:orpheus).orders.order(:created_at).pluck(:prize, :prize_color, :hours).map { |prize, color, hours| [ prize, color, hours.to_i ] }
  end

  test "on a phone the tiles stack two across and Clippy's docked at the bottom" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit shop_path
    assert_selector ".shop__say", text: "link hackatime", wait: 5
    assert_no_selector ".shop__customize", visible: true
    assert_no_selector ".shop__range", visible: true
    assert_selector ".shop__tile", count: Console::ALL.size
    assert_operator find("#shop-miyoo").native.rect.y + 210 + 20, :<, find("#shop-rg28xx").native.rect.y, "the prizes first, then a row of empty cells, then the rest"
    assert_in_delta find("#shop-rg35xx").native.rect.y, find("#shop-miyoo").native.rect.y, 1, "two across"

    find(".shop__choice", text: "colour: gray").click
    assert_selector ".shop__customize", visible: true
    assert_selector ".shop__choice", visible: true, count: 1, text: "back"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
