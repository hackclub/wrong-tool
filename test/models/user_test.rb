require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "signing in for the first time makes a user from Hack Club Auth's claims" do
    user = User.from_omniauth(mock_hack_club_auth)

    assert_equal "ident!heidi", user.hca_id
    assert_equal "heidi@hackclub.com", user.email
    assert_equal "Heidi Hakkuun", user.name
    assert_equal "Heidi", user.first_name
    assert_equal "U0HEIDI", user.slack_id
    assert_equal "verified", user.verification_status
    assert user.ysws_eligible
  end

  test "signing in again finds the same user and refreshes what changed" do
    user = users(:orpheus)
    assert_no_difference -> { User.count } do
      User.from_omniauth(mock_hack_club_auth(uid: user.hca_id, name: "Orpheus Hacksworth", ysws_eligible: false))
    end

    user.reload
    assert_equal "Orpheus Hacksworth", user.name
    assert_not user.ysws_eligible
  end
end
