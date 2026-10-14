require "test_helper"

class Admin::SellerRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ask = projects(:ana).seller_requests.create!(prize: "miyoo", url: "https://www.amazon.de/dp/B0MIYOO")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see who's waiting, with the link, and approve or deny" do
    sign_in_as(users(:orpheus))
    get admin_seller_requests_path

    assert_response :success
    assert_select ".formula-bar__content", /1 waiting/
    assert_select ".admin__nav a[aria-current=page]", "Sellers"
    assert_select "tr##{dom_id(@ask)}", text: /Ana Lovelace.*Miyoo Mini Plus.*amazon\.de/m
    assert_select "tr##{dom_id(@ask)} a[href='https://www.amazon.de/dp/B0MIYOO']", "amazon.de"
    assert_select "tr##{dom_id(@ask)} a[href='https://lomiyoo.com/products/miyoo-mini-plus']", /from Miyoo's store/
    assert_select "tr##{dom_id(@ask)} form[action=?]", admin_seller_request_path(@ask), 2

    patch admin_seller_request_path(@ask), params: { decision: "approved" }
    assert_redirected_to admin_seller_requests_path
    assert @ask.reload.approved?
    assert_equal users(:orpheus), @ask.decided_by
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_match(/it'll come from amazon\.de/, dm[:args].second)

    follow_redirect!
    assert_select ".formula-bar__content", /0 waiting/
    assert_select "tr##{dom_id(@ask)} [data-decision=approved]", /Approved/
    assert_select "tr##{dom_id(@ask)} form", 0

    patch admin_seller_request_path(@ask), params: { decision: "denied" }
    assert @ask.reload.approved?, "the first decision stands"
    assert_equal "That one's been decided already.", flash[:alert]
  end

  test "nobody else can see it, or decide" do
    get admin_seller_requests_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_seller_requests_path
    assert_response :not_found
    patch admin_seller_request_path(@ask), params: { decision: "approved" }
    assert_response :not_found
    assert @ask.reload.pending?
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
