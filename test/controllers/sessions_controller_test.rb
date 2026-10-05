require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { mock_hack_club_auth }

  test "signing in with Hack Club Auth creates the user and returns to where they started" do
    assert_difference -> { User.count } do
      post "/auth/hackclub", params: { origin: onboarding_path }
      follow_redirect!
    end

    assert_redirected_to onboarding_path
    assert_equal User.find_by!(hca_id: "ident!heidi").id, session[:user_id]
  end

  test "signing in adds you to the Slack channels, until you've been added" do
    post "/auth/hackclub"
    assert_enqueued_with(job: JoinSlackChannelsJob) { follow_redirect! }

    User.find_by!(hca_id: "ident!heidi").update!(slack_channels_joined_at: Time.current)
    post "/auth/hackclub"
    assert_no_enqueued_jobs(only: JoinSlackChannelsJob) { follow_redirect! }
  end

  test "won't return anywhere off the site" do
    post "/auth/hackclub", params: { origin: "https://evil.example/phish" }
    follow_redirect!

    assert_redirected_to "/phish"
  end

  test "a failed sign-in goes back to onboarding with the reason" do
    get auth_failure_path, params: { message: "access_denied" }

    assert_redirected_to onboarding_path
    assert_equal "Couldn't sign you in with Hack Club (access denied).", flash[:alert]
  end

  test "logging out ends the session" do
    post "/auth/hackclub"
    follow_redirect!
    delete logout_path

    assert_redirected_to root_path
    assert_nil session[:user_id]
  end
end
