require "test_helper"

class BuddyInvitesControllerTest < ActionDispatch::IntegrationTest
  test "anyone can see who's inviting them and what they'd both get" do
    get buddy_invite_path("k3j9x2qa")

    assert_response :success
    assert_select ".buddy-invited__title", "pixelana invited you to build together."
    assert_no_match(/Ana|Lovelace/, response.body, "never their real name")
    assert_select ".buddy-card__title", "Pong in Figma"
    assert_equal [ "Shown as a pair on the leaderboard", "Sticker sheet each", "A mention in #wrong", "Pick Kartikey's desktop background" ],
                 css_select(".buddy-invited__reward span:last-child").map(&:text)
    assert_select "button", "Pair up"
  end

  test "a link that doesn't exist says so" do
    get buddy_invite_path("nobody")
    assert_response :not_found
    assert_select "h1", "This invite link isn't valid."
  end

  test "accepting pairs you up" do
    sign_in_as_orpheus
    post buddy_invite_path("k3j9x2qa")

    assert_redirected_to buddy_path
    assert_equal projects(:ana), projects(:orpheus).reload.buddy
    assert_equal projects(:orpheus), projects(:ana).reload.buddy
    follow_redirect!
    assert_select "h1", "You + pixelana"
    assert_select ".formula-bar__content", /=BUDDY\(you, pixelana\) → TRUE/
    assert_select ".sheet-tab__count", "1"

    get buddy_invite_path("k3j9x2qa")
    assert_select ".project__step-error", "You already have a buddy."
    assert_select "button", text: "Pair up", count: 0
  end

  test "without a project yet, accepting waits until you've signed your pledge" do
    mock_hack_club_auth
    post "/auth/hackclub"
    follow_redirect!
    post buddy_invite_path("k3j9x2qa")
    assert_redirected_to onboarding_path

    post project_path, as: :json, params: { project: { tool: "email", tool_name: "Email", idea: "a mail RPG", prize: "miyoo",
                                                       pace_minutes: 20, build_time: "evening" } }
    assert_equal buddy_path, response.parsed_body["location"]
    assert_equal projects(:ana), User.find_by!(hca_id: "ident!heidi").project.buddy
  end

  test "your own link is yours" do
    mock_hack_club_auth(uid: users(:ana).hca_id, slack_id: "U0ANA")
    post "/auth/hackclub"
    follow_redirect!
    get buddy_invite_path("k3j9x2qa")

    assert_select ".buddy-invited__title", "This is your own invite link."
    assert_select "button", text: "Pair up", count: 0
  end

  private
    def sign_in_as_orpheus
      mock_hack_club_auth(uid: users(:orpheus).hca_id, slack_id: "U0ORPHEUS")
      post "/auth/hackclub"
      follow_redirect!
    end
end
