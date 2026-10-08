require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see everyone, with a way to view as anyone who isn't an admin" do
    sign_in_as(users(:orpheus))
    get admin_users_path

    assert_response :success
    assert_select "tr##{dom_id(users(:ana))}", text: /Ana Lovelace.*ana@hackclub\.com.*pixelana/m
    assert_select "tr##{dom_id(users(:ana))} form[action=?]", admin_user_impersonation_path(users(:ana))
    assert_select "tr##{dom_id(users(:orpheus))} form", 0
    assert_select "tr##{dom_id(users(:orpheus))}", text: /admin/
  end

  test "searching narrows it" do
    sign_in_as(users(:orpheus))
    get admin_users_path(q: "pixel")

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "tr##{dom_id(users(:ana))}"
  end

  test "nobody else can see it" do
    get admin_users_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_users_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
