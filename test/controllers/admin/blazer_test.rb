require "test_helper"

class Admin::BlazerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins can open it" do
    sign_in_as(users(:orpheus))
    get "/admin/blazer"
    assert_response :success
  end

  test "nobody else can find it" do
    get "/admin/blazer"
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id)
      post "/auth/hackclub"
      follow_redirect!
    end
end
