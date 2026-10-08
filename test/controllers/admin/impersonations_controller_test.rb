require "test_helper"

class Admin::ImpersonationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0HEIDI" ]
    @heidi = User.create!(hca_id: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi", slack_id: "U0HEIDI")
    @newcomer = User.create!(hca_id: "ident!newcomer", email: "new@hackclub.com", name: "Nova Newcomer", first_name: "Nova")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "an admin sees the site as someone, then gets their own session back" do
    sign_in_as(users(:orpheus))

    post admin_user_impersonation_path(users(:ana))
    assert_redirected_to project_path # Ana's pledged, so her project
    assert_equal users(:ana).id, session[:user_id]
    assert_equal users(:orpheus).id, session[:impersonator_id]

    get project_path
    assert_response :success
    assert_select ".impersonation", text: /Viewing as Ana Lovelace.*you're Orpheus/m
    assert_select ".impersonation form[action=?]", admin_impersonation_path
    assert_select "body[data-posthog-user-id]", 0

    get admin_users_path
    assert_response :not_found # Ana isn't an admin, so neither is the site right now

    delete admin_impersonation_path
    assert_redirected_to admin_users_path
    assert_equal users(:orpheus).id, session[:user_id]
    assert_nil session[:impersonator_id]

    get admin_users_path
    assert_response :success
    assert_select ".impersonation", 0
  end

  test "viewing as someone who hasn't pledged lands on onboarding" do
    sign_in_as(users(:orpheus))

    post admin_user_impersonation_path(@newcomer)
    assert_redirected_to onboarding_path
  end

  test "the admin's browser timezone doesn't become theirs" do
    users(:ana).update!(timezone: "Europe/Berlin")
    sign_in_as(users(:orpheus))
    post admin_user_impersonation_path(users(:ana))

    cookies[:timezone] = "America/New_York"
    get project_path
    assert_equal "Europe/Berlin", users(:ana).reload.timezone
  end

  test "not yourself, not another admin" do
    sign_in_as(users(:orpheus))

    post admin_user_impersonation_path(users(:orpheus))
    assert_redirected_to admin_users_path
    assert_nil session[:impersonator_id]

    post admin_user_impersonation_path(@heidi)
    assert_redirected_to admin_users_path
    assert_nil session[:impersonator_id]
  end

  test "nobody else can start one, and stopping without one goes home" do
    post admin_user_impersonation_path(users(:ana))
    assert_response :not_found

    sign_in_as(users(:ana))
    post admin_user_impersonation_path(@heidi)
    assert_response :not_found

    delete admin_impersonation_path
    assert_redirected_to root_path
    assert_equal users(:ana).id, session[:user_id]
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
