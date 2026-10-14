require "test_helper"

class Admin::OrdersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @order = projects(:ana).orders.new(prize: "miyoo", prize_color: "purple", prize_options: { storage: "64" }, hours: 10,
                                       seller_url: "https://www.amazon.de/dp/B0MIYOO")
    @order.save!(validate: false) # as if their approved hours covered it
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see what's to order, from where, and mark it ordered" do
    sign_in_as(users(:orpheus))
    get admin_orders_path

    assert_response :success
    assert_select ".formula-bar__content", /1 to order/
    assert_select ".admin__nav a[aria-current=page]", "Orders"
    assert_select "tr##{dom_id(@order)}", text: /Ana Lovelace.*ana@hackclub\.com.*Miyoo Mini Plus in purple, 64GB.*amazon\.de.*a seller we approved.*10 hrs/m
    assert_select "tr##{dom_id(@order)} a[href='https://www.amazon.de/dp/B0MIYOO']", "amazon.de"

    patch admin_order_path(@order)
    assert_redirected_to admin_orders_path
    assert @order.reload.ordered?
    assert_equal users(:orpheus), @order.ordered_by
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_match(/Your Miyoo Mini Plus in purple, 64GB is ordered\. It'll get to you from amazon\.de\./, dm[:args].second)

    follow_redirect!
    assert_select ".formula-bar__content", /0 to order/
    assert_select "tr##{dom_id(@order)} form", 0
    assert_select "tr##{dom_id(@order)} [data-decision=approved]", /Orpheus/

    patch admin_order_path(@order)
    assert_equal "That one's been ordered already.", flash[:alert]
  end

  test "nobody else can see it, or order" do
    get admin_orders_path
    assert_response :not_found

    sign_in_as(users(:ana))
    patch admin_order_path(@order)
    assert_response :not_found
    assert @order.reload.waiting?
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
