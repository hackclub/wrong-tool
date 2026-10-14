require "test_helper"

class Admin::ShipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ship = projects(:ana).ships.create!(title: "Pong in Figma", description: "Two paddles, one ball, and every frame is a Figma component.",
                                         repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong",
                                         hackatime_projects: [ "pong" ], hours: 7.5, screenshot: screenshot_upload, screenshot_shows_game: true)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see every ship, open one in full, and approve it" do
    sign_in_as(users(:orpheus))
    get admin_ships_path

    assert_response :success
    assert_select ".formula-bar__content", /1 in review/
    assert_select ".admin__nav a[aria-current=page]", "Ships"
    assert_select ".leaderboard__note", /7\.5 hrs across every project/
    assert_select "tr##{dom_id(@ship)}", text: /Ana Lovelace.*Pong in Figma.*Figma · pong.*7\.5.*In review/m
    assert_select "tr##{dom_id(@ship)} a[href=?]", admin_ship_path(@ship), "Pong in Figma"

    get admin_ship_path(@ship)
    assert_response :success
    assert_select "h1", "Pong in Figma"
    assert_select ".leaderboard__note", /by\s+Ana Lovelace \(ana@hackclub\.com, pixelana on Slack\)/m
    assert_select ".admin__tile", text: /Hours when shipped\s*7\.5/m
    assert_select ".admin__ship-details a[href='https://github.com/ana/pong']"
    assert_select ".admin__ship-details a[href='https://example.com/pong']"
    assert_select ".admin__ship-description", /every frame is a Figma component/
    assert_select ".admin__ship-shot img[alt='Screenshot of Pong in Figma']"
    assert_select "form[action=?]", admin_ship_path(@ship), 2
    assert_select "form[action=?] input[name=approved_hours][value='7.5'][max='7.5']", admin_ship_path(@ship)

    patch admin_ship_path(@ship), params: { decision: "approved", approved_hours: "6" }
    assert_redirected_to admin_ship_path(@ship)
    assert @ship.reload.approved?
    assert_equal 6, @ship.approved_hours, "what the admin approved, not all 7.5"
    assert_equal 6, projects(:ana).reload.hours_approved
    assert_equal users(:orpheus), @ship.decided_by
    assert projects(:ana).reload.shipped?

    follow_redirect!
    assert_select ".admin__tile [data-decision=approved]", "Approved"
    assert_select "form[action=?]", admin_ship_path(@ship), 0, "decided, so no buttons"
    assert_select "[data-decision=approved]", /Approved · Orpheus · #{Date.current.strftime("%b %-d")}/

    patch admin_ship_path(@ship), params: { decision: "rejected" }
    assert @ship.reload.approved?, "the first decision stands"
    assert_equal "That one's been decided already.", flash[:alert]

    get admin_ships_path
    assert_select ".formula-bar__content", /0 in review/
    assert_select "tr##{dom_id(@ship)} [data-decision=approved]", /Approved.*Orpheus/m
  end

  test "sending a ship back lets them ship again, and the earlier one shows under the new" do
    sign_in_as(users(:orpheus))
    patch admin_ship_path(@ship), params: { decision: "rejected" }
    assert @ship.reload.rejected?
    assert_nil projects(:ana).reload.ship_in_review
    assert_not projects(:ana).shipped?

    again = projects(:ana).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url", "hackatime_projects")
                                              .merge(hours: 9, screenshot: screenshot_upload, screenshot_shows_game: true))
    get admin_ship_path(again)
    assert_select "#admin-ship-others", "Earlier ships of this project"
    assert_select "tr##{dom_id(@ship)} [data-decision=rejected]", /Sent back/
    assert_select "tr##{dom_id(again)}", 0

    get admin_ships_path
    assert_select ".leaderboard__note", /9 hrs across every project/, "only the ship that stands counts"
  end

  test "nobody else can see them, or decide" do
    get admin_ships_path
    assert_response :not_found
    get admin_ship_path(@ship)
    assert_response :not_found
    patch admin_ship_path(@ship), params: { decision: "approved" }
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_ships_path
    assert_response :not_found
    get admin_ship_path(@ship)
    assert_response :not_found
    patch admin_ship_path(@ship), params: { decision: "approved" }
    assert_response :not_found
    assert @ship.reload.in_review?
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end

    def screenshot_upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end
end
