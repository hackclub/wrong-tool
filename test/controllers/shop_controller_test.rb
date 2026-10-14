require "test_helper"

class ShopControllerTest < ActionDispatch::IntegrationTest
  test "without a project, it's back to onboarding" do
    get shop_path
    assert_redirected_to onboarding_path

    sign_in_as(mock_hack_club_auth)
    get shop_path
    assert_redirected_to onboarding_path
  end

  test "the shop is a shelf of every console in hours, never prices, with yours flagged and Clippy at the counter" do
    projects(:orpheus).update!(prize_color: "purple")
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    get shop_path

    assert_response :success
    assert_select ".shop__title-text", "Shop"
    assert_select ".shop__tile", Console::ALL.size
    assert_select ".shop__tile[data-yours][data-selected]", 1
    assert_select "#shop-miyoo[data-yours][data-state=locked] .shop__tile-button[aria-pressed=true]"
    assert_select "#shop-rg35xxsp:not([data-yours]) .shop__tile-button[aria-pressed=false]"
    # The two we promised first, then the rest by hours, three columns each from A4.
    assert_equal %w[rg35xx miyoo rg28xx v90s rg35xxsp miyooflip rg34xxsp rgdsplus rpclassic chromatic rpduolite rp5 rpflip2], css_select(".shop__tile").map { |tile| tile["data-console"] }
    assert_select ".shop__shelf-head", 0, "no headings over the shelf"
    assert_equal %w[A4 D4 H4 K4 N4 Q4 T4 W4 Z4 AC4 AF4 AI4 AL4], css_select("[data-controller=shop]").first["data-shop-consoles-value"].then { |json| JSON.parse(json).map { |console| console["cell"] } }, "a column of empty cells after the prizes"
    assert_select ".shop__tile[data-group=prize] + .shop__shelf-gap", "or swap for one of these"
    assert_select ".shop__title", "Shop"
    assert_select ".shop__keeper-label", "CLIPPY"
    assert_select ".shop__tile[data-group=prize]", 2
    assert_select ".formula-bar__name", "D4"
    assert_equal %w[D E F], css_select(".shop__column-header[data-selected]").map(&:text)
    assert_equal %w[4 5 6 7 8 9 10], css_select(".shop__row-header[data-selected]").map(&:text)
    assert_select "#shop-miyoo .shop__tile-cost", "10 hrs"
    assert_select "#shop-miyoo .shop__tile-tag", "10 to go"
    assert_select "#shop-rg35xx .shop__tile-cost", "10 hrs"
    assert_select "#shop-rg28xx .shop__tile-cost", "8 hrs"
    assert_select ".shop__stat--logged .shop__stat-value", "0 hrs"
    assert_select ".shop__stat--ship .shop__stat-value[data-tone=none]", "not yet"
    # The Customize panel starts on yours: the colour you picked, and the extras it comes with, in hours.
    assert_select "[data-shop-target=customizeName]", "Mini Plus"
    assert_select ".shop__variant", "Purple"
    assert_select ".shop__swatch[aria-pressed=true][data-color=purple]"
    assert_select ".shop__chip[aria-pressed=true][data-option=storage][data-choice='64']"
    assert_equal [ "included", "included" ], css_select(".shop__chip-more").map(&:text), "a card or none, as Miyoo sells it, and no bag"
    assert_select ".shop__customize-cost", "10 hrs"
    assert_select ".shop__say [data-shop-target=typed]", "link hackatime on your sheet and your hours will show up here."
    assert_select "a.shop__customize-value[href='https://lomiyoo.com/products/miyoo-mini-plus']", "Miyoo's store"
    assert_select ".sheet-tab[aria-current=page]", "Shop"
    assert_select ".sheet-tabs__sum", "Mini Plus · 10 hrs to go"
    assert_no_match(/\$\d/, css_select("main").to_s, "no prices anywhere on the sheet")
    assert_no_match(/\$\d|price/i, css_select("[data-controller=shop]").first["data-shop-consoles-value"], "the shelf's data is hours, not prices")
  end

  test "Clippy says where your hours are, and the shelf unlocks as they cover a tile" do
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    with_hackatime_hours(8) do
      get shop_path
      assert_select ".shop__say [data-shop-target=typed]", "8 hours so far, 2 to go for the Mini Plus in gray."
      assert_select ".shop__stat--logged .shop__stat-value", "8 hrs"
      assert_select "#shop-rg28xx[data-state=unlocked] .shop__tile-tag", "ship first"
      assert_select "#shop-rg35xx[data-state=locked] .shop__tile-tag", "2 to go"
      assert_select ".formula-bar__content", /=PICK\("miyoo", "grey"\)\s+→\s+8 of 10 hrs/

      patch shop_path, params: { project: { prize: "rg28xx", prize_color: "black" } }
      follow_redirect!
      # With an emote on the end, as the picture Slack shows for it.
      assert_select ".shop__say [data-shop-target=typed]", "RG28XX in black transparent. your hours cover it, so ship your game and it's yours."
      assert_select ".shop__say img.emote[src='/emotes/yay.gif'][alt=':yay:']"
      assert_equal({ "yay" => "/emotes/yay.gif" }, JSON.parse(css_select("[data-controller=shop]").first["data-shop-emotes-value"]))
      assert_select "#shop-rg28xx[data-yours][data-state=unlocked] .shop__tile-tag", "ship first"
      assert_select ".shop__tile-stamp", 0, "nothing stamped across the tiles"
      assert_select ".sheet-tabs__sum", "RG28XX · hours in"
    end
  end

  test "picking a console, and a colour and extras on it, from the page or from the counter" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch shop_path, params: { project: { prize: "rg35xxsp", prize_color: "green" } }
    assert_redirected_to shop_path
    assert_equal [ "rg35xxsp", "green" ], projects(:orpheus).reload.values_at(:prize, :prize_color)
    follow_redirect!
    assert_select ".shop__say [data-shop-target=typed]", "RG35XX SP in green transparent. 12 hours to go."
    assert_select "#shop-rg35xxsp[data-yours][data-selected]"

    # From the counter: JSON back, with what Clippy says.
    patch shop_path, params: { project: { prize: "rg35xxsp", prize_color: "green", prize_options: { storage: "128", bag: "yes" } } }, as: :json
    assert_response :success
    state = response.parsed_body
    assert_equal({ "storage" => "128", "bag" => "yes" }, projects(:orpheus).reload.prize_options)
    assert_equal 97.98, projects(:orpheus).prize_price
    assert_equal "rg35xxsp", state["prize"]
    assert_equal "green", state["prize_color"]
    assert_equal({ "storage" => "128", "bag" => "yes" }, state["prize_options"])
    assert_equal 22, state["hours_needed"]
    assert_equal "RG35XX SP in green transparent. 22 hours to go.", state["says"]
    assert_equal "RG35XX SP · 22 hrs to go", state["sum"]
    assert_match(/=PICK\("rg35xxsp", "green"\)/, state["formula"])
    assert_nil state["price"], "no prices for the page"

    patch shop_path, params: { project: { prize: "rg35xxsp", prize_color: "black" } }
    assert_equal "black", projects(:orpheus).reload.prize_color

    # Changing console drops the colour unless the new one comes in it too.
    patch shop_path, params: { project: { prize: "rg34xxsp", prize_color: "silver" } }
    assert_equal [ "rg34xxsp", nil ], projects(:orpheus).reload.values_at(:prize, :prize_color)
    assert_equal "yellow", projects(:orpheus).console_color.id
  end

  test "a colour the console doesn't come in, or a console that isn't one, is sent back" do
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    patch shop_path, params: { project: { prize: "miyoo", prize_color: "plaid" } }
    assert_response :unprocessable_entity
    assert_select ".shop__say [data-shop-target=typed]", /Prize color isn't one the Mini Plus comes in/
    assert_nil projects(:orpheus).reload.prize_color

    patch shop_path, params: { project: { prize: "switch", prize_color: "grey" } }
    assert_response :unprocessable_entity
    assert_equal "miyoo", projects(:orpheus).reload.prize

    patch shop_path, params: { project: { prize: "miyoo", prize_options: { storage: "1tb" } } }, as: :json
    assert_response :unprocessable_entity
    assert_match(/Prize options include storage, which the Mini Plus doesn't offer/, response.parsed_body["error"])
    assert_equal({}, projects(:orpheus).reload.prize_options)
  end

  test "an approved ship's hours are spent like money: buy anything they cover, one of each, till they're gone" do
    approve_ship(hours: 20)
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))

    get shop_path
    assert_select ".shop__say [data-shop-target=typed]", "20 hours to spend. that covers the Mini Plus in gray, so it's yours to buy."
    assert_select "#shop-miyoo[data-state=ready] .shop__tile-tag", "ready"
    assert_select "#shop-rg35xxsp[data-state=ready] .shop__tile-tag", "ready", "12 hrs, and 20 to spend"
    assert_select "#shop-rgdsplus[data-state=locked]"
    assert_select ".shop__stat--ship .shop__stat-label", "TO SPEND"
    assert_select ".shop__stat--ship .shop__stat-value[data-tone=done]", "20 hrs"
    assert_select ".sheet-tabs__sum", "Mini Plus · ready"
    assert_select "[data-controller=shop][data-shop-to-spend-value='20.0'][data-shop-orders-value='{}']"

    # Something that isn't your pick, as it's set up on its tile.
    post shop_order_path, params: { order: { prize: "rg35xxsp", prize_color: "green", prize_options: { storage: "64", bag: "no" } } }, as: :json
    assert_response :success
    assert_equal({ "prize" => "rg35xxsp", "order" => "waiting", "hours_to_spend" => 8.0, "hours_spent" => 12.0 }, response.parsed_body.except("sum", "formula"))
    assert_match(/=BUY\("rg35xxsp", "green"\)\s+→\s+8 hrs left/, response.parsed_body["formula"])
    assert_equal [ "green", 12 ], projects(:orpheus).orders.sole.values_at(:prize_color, :hours)

    get shop_path
    assert_select "#shop-rg35xxsp[data-state=shipping] .shop__tile-tag", "in the queue"
    assert_select "#shop-rg28xx[data-state=ready]", 1, "8 hrs, and 8 left"
    assert_select "#shop-miyoo[data-state=locked]", 1, "10 hrs, and 8 left"
    assert_select ".shop__stat--ship .shop__stat-value", "8 hrs"
    assert_select "[data-controller=shop][data-shop-orders-value=?]", { rg35xxsp: "waiting" }.to_json

    post shop_order_path, params: { order: { prize: "rg35xxsp" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "RG35XX SP is one you've bought already", response.parsed_body["error"]
    post shop_order_path, params: { order: { prize: "miyoo" } }, as: :json
    assert_equal "That's 10 hours, and you've 8 approved to spend.", response.parsed_body["error"]

    # Your pick changes whenever: it's what you're working towards.
    patch shop_path, params: { project: { prize: "rg28xx", prize_color: "black" } }
    assert_equal "rg28xx", projects(:orpheus).reload.prize
    post shop_order_path, params: { order: { prize: "rg28xx", prize_color: "black" } }, as: :json
    assert_response :success
    get shop_path
    assert_select ".shop__say [data-shop-target=typed]", "your RG28XX in black transparent is bought. someone will order it soon."
    assert_select ".sheet-tabs__sum", "RG28XX · in the queue"

    projects(:orpheus).orders.find_by(prize: "rg28xx").ordered!(by: users(:ana))
    get shop_path
    assert_select "#shop-rg28xx .shop__tile-tag", "ordered"
  end

  test "approved hours that don't cover your pick can't buy it, and logged ones don't count till they're shipped" do
    approve_ship(hours: 8)
    link_hackatime(users(:orpheus))
    projects(:orpheus).update!(hackatime_projects: [ "rhythm-game" ])
    sign_in_as(mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS"))
    with_hackatime_hours(14) do
      get shop_path
      assert_select ".shop__say [data-shop-target=typed]", "8 hours to spend. ship again so the rest count for the Mini Plus in gray."
      assert_select "#shop-miyoo[data-state=unlocked] .shop__tile-tag", "ship again"
      assert_select "#shop-rg28xx[data-state=ready]", 1, "8 hrs, and 8 approved"

      post shop_order_path, params: { order: { prize: "miyoo" } }, as: :json
      assert_response :unprocessable_entity
      assert_equal "That's 10 hours, and you've 8 approved to spend.", response.parsed_body["error"]
      assert_empty projects(:orpheus).reload.orders
    end
  end

  private
    def approve_ship(hours:)
      projects(:orpheus).ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, built in Sheets.",
                                       repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                                       screenshot: fixture_file_upload("screenshot.png", "image/png"), screenshot_shows_game: true)
                         .decide!("approved", by: users(:ana))
    end

    def sign_in_as(_auth)
      post "/auth/hackclub"
      follow_redirect!
    end
end
