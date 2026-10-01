require "test_helper"

class HackatimeLinksControllerTest < ActionDispatch::IntegrationTest
  test "linking Hackatime keeps who you are there and ticks off the step" do
    sign_in_as_orpheus
    mock_hackatime(token: "token-orpheus")
    post "/auth/hackatime"
    follow_redirect!

    assert_redirected_to project_path
    assert_equal "hop", flash[:clippy]
    user = users(:orpheus).reload
    assert_equal [ "1001", "token-orpheus" ], [ user.hackatime_uid, user.hackatime_access_token ]
    assert_not_equal "token-orpheus", User.connection.select_value("SELECT hackatime_access_token FROM users WHERE id = #{user.id}"),
                     "the token's stored encrypted"
    assert projects(:orpheus).step_done?("hackatime")
  end

  test "a token Hackatime doesn't recognize links nothing" do
    sign_in_as_orpheus
    mock_hackatime(token: "nonsense")
    post "/auth/hackatime"
    follow_redirect!

    assert_redirected_to project_path
    assert_equal "Couldn't tell who you are on Hackatime. Try again.", flash[:alert]
    assert_not users(:orpheus).reload.hackatime_linked?
  end

  test "a Hackatime account can only be linked to one person" do
    User.create!(hca_id: "ident!someone", name: "Someone", hackatime_uid: "1001", hackatime_access_token: "theirs")
    sign_in_as_orpheus
    mock_hackatime(token: "token-orpheus")
    post "/auth/hackatime"
    follow_redirect!

    assert_equal "That Hackatime account is already linked to someone else here.", flash[:alert]
    assert_not users(:orpheus).reload.hackatime_linked?
  end

  test "saying no on Hackatime comes back to your project" do
    sign_in_as_orpheus
    get "/auth/failure", params: { message: "access_denied", strategy: "hackatime" }

    assert_redirected_to project_path
    assert_equal "Couldn't link Hackatime (access denied). Try again.", flash[:alert]
  end

  private
    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
