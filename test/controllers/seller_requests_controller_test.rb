require "test_helper"

class SellerRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0KARTIKEY" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "sending a link from the counter: saved, the admins told, and the ask back as the shop shows it" do
    sign_in_as(users(:orpheus))
    post shop_seller_requests_path, params: { seller_request: { prize: "miyoo", url: "https://www.amazon.de/dp/B0MIYOO" } }, as: :json

    assert_response :success
    assert_equal({ "url" => "https://www.amazon.de/dp/B0MIYOO", "host" => "amazon.de", "status" => "pending", "label" => "in review" }, response.parsed_body)
    ask = projects(:orpheus).seller_requests.sole
    assert_equal [ "miyoo", "pending" ], [ ask.prize, ask.status ]
    assert_equal [ "U0KARTIKEY" ], enqueued_jobs.select { |job| job[:job] == SlackMessageJob }.map { |job| job[:args].first }

    # The shop says so on the tile.
    get shop_path
    assert_select "a.shop__customize-value[href='https://www.amazon.de/dp/B0MIYOO']", "amazon.de · in review"
    assert_equal "in review", JSON.parse(css_select("[data-controller=shop]").first["data-shop-asks-value"]).dig("miyoo", "label")

    post shop_seller_requests_path, params: { seller_request: { prize: "miyoo", url: "https://example.com/again" } }, as: :json
    assert_response :unprocessable_entity
    assert_equal "There's a link in for the Mini Plus already", response.parsed_body["error"]

    post shop_seller_requests_path, params: { seller_request: { prize: "miyoo", url: "https://lomiyoo.com/products/miyoo-mini-plus" } }, as: :json
    assert_response :unprocessable_entity
  end

  test "after a no, the shop's back to the store, and another link can go in" do
    ask = projects(:orpheus).seller_requests.create!(prize: "miyoo", url: "https://shop.example/miyoo")
    ask.decide!("denied", by: users(:ana))
    sign_in_as(users(:orpheus))

    get shop_path
    assert_select "a.shop__customize-value[href='https://lomiyoo.com/products/miyoo-mini-plus']", "Miyoo's store"
    post shop_seller_requests_path, params: { seller_request: { prize: "miyoo", url: "https://shop.example/miyoo-2" } }, as: :json
    assert_response :success
  end

  test "not without a project" do
    post shop_seller_requests_path, params: { seller_request: { prize: "miyoo", url: "https://example.com/a" } }, as: :json
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
