require "test_helper"

class OrderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0KARTIKEY" ]
    @project = projects(:orpheus)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "approved hours are spent like money: one of each console, as many as they cover, each exactly as set up" do
    assert_not buy("rg28xx").persisted?, "nothing approved yet"

    approve(hours: 30)
    assert_equal 30, @project.hours_to_spend

    first = buy("rg35xxsp", prize_color: "green", prize_options: { storage: "64", bag: "no" })
    assert first.persisted?
    assert first.waiting?
    assert_equal [ "rg35xxsp", "green", { "storage" => "64", "bag" => "no" }, 12, "https://anbernic.com/products/rg35xxsp" ],
                 [ first.prize, first.prize_color, first.prize_options, first.hours, first.seller_url ]
    assert_equal "ANBERNIC RG35XX SP in green transparent", first.configuration
    assert_equal [ 12, 18 ], [ @project.reload.hours_spent, @project.hours_to_spend ]

    # Not your pick, and every option filled in as it comes.
    second = buy("rg28xx")
    assert_equal [ "beige", { "storage" => "32", "bag" => "no" }, 8 ], [ second.prize_color, second.prize_options, second.hours ]
    assert_equal 10, @project.reload.hours_to_spend

    again = buy("rg28xx")
    assert_not again.persisted?
    assert_equal "RG28XX is one you've bought already", again.problem

    too_much = buy("rg34xxsp")
    assert_equal "That's 15 hours, and you've 10 approved to spend.", too_much.problem
    assert_equal "That colour isn't one the Mini Plus comes in.", buy("miyoo", prize_color: "plaid").problem
    assert_equal "The Mini Plus doesn't come with that.", buy("miyoo", prize_options: { bag: "yes" }).problem

    assert buy("miyoo").persisted?, "10 left, and the Mini Plus is 10"
    assert_equal 0, @project.reload.hours_to_spend
  end

  test "buying tells the admins what to order, and from where" do
    approve(hours: 12)
    buy("rg35xxsp", prize_color: "green").then { |order| OrderNotifier.claimed(order) }
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0KARTIKEY" }
    assert_equal "Orpheus the Dino claimed the ANBERNIC RG35XX SP in green transparent with 12 approved hours. " \
                 "Order it from Anbernic's store:\nhttps://anbernic.com/products/rg35xxsp", dm[:args].second
    assert_equal [ "Open the queue", "https://wrong.hackclub.com/admin/orders" ], dm[:args].third["link"]
  end

  test "from a seller an admin approved for that console, if there is one" do
    approve(hours: 10)
    @project.seller_requests.create!(prize: "miyoo", url: "https://www.amazon.de/dp/B0MIYOO").decide!("approved", by: users(:ana))
    order = buy("miyoo")
    assert_equal "https://www.amazon.de/dp/B0MIYOO", order.seller_url
    assert_equal "amazon.de", order.seller_name
  end

  test "an admin orders it once, and Clippy DMs them" do
    approve(hours: 10)
    order = buy("miyoo")
    travel_to Time.utc(2026, 10, 20, 12) do
      assert order.ordered!(by: users(:ana))
    end
    assert_equal [ "ordered", users(:ana), Time.utc(2026, 10, 20, 12) ], [ order.status, order.ordered_by, order.ordered_at ]
    assert_not order.ordered!(by: users(:ana))

    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_equal "Your Miyoo Mini Plus in gray, 64GB is ordered. It'll get to you from Miyoo's store.\n" \
                 ":clippy-excited: clippy is doing a little dance. :partyparrot:", dm[:args].second
  end

  private
    def buy(prize, **picks)
      @project.reload.orders.create(prize:, **picks)
    end

    def approve(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, built in Sheets.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", hours:,
                             screenshot: Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png"), screenshot_shows_game: true)
              .decide!("approved", by: users(:ana))
    end
end
