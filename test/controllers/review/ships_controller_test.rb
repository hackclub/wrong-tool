require "test_helper"

class Review::ShipsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    @ship = projects(:ana).ships.create!(title: "Pong in Figma", description: "Two paddles, one ball, and every frame is a Figma component.",
                                         repo_url: "https://github.com/ana/pong", demo_url: "https://example.com/pong",
                                         hackatime_projects: [ "pong" ], hours: 7.5, screenshot: screenshot_upload, screenshot_shows_game: true)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see the queue, open a ship in full, and approve it with fewer hours and why" do
    sign_in_as(users(:orpheus))
    get review_root_path

    assert_response :success
    assert_select ".formula-bar__content", /1 waiting/
    assert_select ".admin__nav a[aria-current=page]", "Queue"
    assert_select ".admin__nav a[href=?]", admin_root_path, "Admin"
    assert_select "tr##{dom_id(@ship)}", text: /Ana Lovelace.*Pong in Figma.*Figma · pong.*7\.5.*In review/m
    assert_select "tr##{dom_id(@ship)} a[href=?]", review_ship_path(@ship), "Pong in Figma"

    get review_ship_path(@ship)
    assert_response :success
    assert_select "h1", "Pong in Figma"
    assert_select ".leaderboard__note", /by\s+Ana Lovelace \(ana@hackclub\.com, pixelana on Slack\)/m
    assert_select ".admin__tile", text: /Hours when shipped\s*7\.5/m
    assert_select ".admin__ship-details a[href='https://github.com/ana/pong']"
    assert_select ".admin__ship-shot img[alt='Screenshot of Pong in Figma']"
    assert_select "#review-history + p", /None yet/
    assert_select "form[action=?]", review_ship_decisions_path(@ship) do
      assert_select "input[type=radio][name='review[decision]']", 3
      assert_select "input[type=radio][value=approved][checked]"
      assert_select "input[name='review[approved_hours]'][value='7.5'][max='7.5']"
    end

    post review_ship_decisions_path(@ship), params: { review: { decision: "approved", approved_hours: "6", justification: "short" } }
    assert_response :unprocessable_entity
    assert_select ".review__errors li", /Justification needs at least 30/
    assert_select ".review__errors li", /Deflation reason needs at least 10/
    assert_select "input[name='review[approved_hours]'][value='6.0']", 1, "what they typed stays"
    assert @ship.reload.in_review?

    post review_ship_decisions_path(@ship), params: { review: { decision: "approved", approved_hours: "6", deflation_reason: "1.5h was another game",
                                                                justification: "Played it to 10 points; each frame really is a component." } }
    assert_redirected_to review_root_path
    assert_equal "Pong in Figma: approved.", flash[:notice]
    assert @ship.reload.approved?
    assert_equal [ 6, users(:orpheus) ], [ @ship.approved_hours, @ship.decided_by ]
    assert_equal [ "U0ANA" ], enqueued_jobs.select { |job| job[:job] == SlackMessageJob }.map { |job| job[:args].first }

    get review_ship_path(@ship)
    assert_select "form[action=?]", review_ship_decisions_path(@ship), 0, "decided, so no form"
    assert_select ".review__panel [data-decision=approved]", /Approved · Orpheus · #{Date.current.strftime("%b %-d")}, with 6 hrs to spend/
    assert_select ".review__call[data-decision=approved]", text: /Approved.*Orpheus.*6 hrs.*Staff only:.*each frame.*Fewer hours because:.*another game/m

    get review_root_path
    assert_select ".formula-bar__content", /0 waiting/
    assert_select "#review-decided ~ div tr##{dom_id(@ship)} [data-decision=approved]", /Approved.*Orpheus/m
  end

  test "asked for changes, they can ship again, and the new ship shows the call on the earlier one" do
    users(:orpheus).update!(review_roles: [ "reviewer" ])
    Rails.configuration.x.admin_slack_ids = []
    sign_in_as(users(:orpheus))
    post review_ship_decisions_path(@ship), params: { review: { decision: "changes_requested", note_to_maker: "The demo link asks me to sign in." } }
    assert @ship.reload.changes_requested?
    assert_nil projects(:ana).reload.ship_in_review

    again = projects(:ana).ships.create!(@ship.attributes.slice("title", "description", "repo_url", "demo_url", "hackatime_projects")
                                              .merge(hours: 9, screenshot: screenshot_upload, screenshot_shows_game: true))
    get review_ship_path(again)
    assert_select ".review__call[data-decision=changes_requested]", text: /Asked for changes.*an earlier ship \(7\.5 hrs\).*To them:.*sign in/m
    assert_select "#review-others", "Earlier ships of this project"
    assert_select "tr##{dom_id(@ship)} [data-decision=changes_requested]", /Changes requested/
    assert_select ".admin__nav a[href=?]", admin_root_path, 0, "not an admin"

    get review_root_path
    assert_select "#review-waiting ~ div tr##{dom_id(again)}"
  end

  test "reviewers never open their own ship" do
    users(:ana).update!(review_roles: [ "reviewer" ])
    sign_in_as(users(:ana))
    get review_root_path
    assert_select "tr##{dom_id(@ship)}", text: /Pong in Figma \(yours\)/
    assert_select "tr##{dom_id(@ship)} a[href=?]", review_ship_path(@ship), 0

    get review_ship_path(@ship)
    assert_response :not_found
    post review_ship_decisions_path(@ship), params: { review: { decision: "rejected", note_to_maker: "Rejecting my own ship." } }
    assert_response :not_found
    assert @ship.reload.in_review?
  end

  test "fraud reviewers can look, but not decide" do
    users(:orpheus).update!(review_roles: [ "fraud" ])
    Rails.configuration.x.admin_slack_ids = []
    sign_in_as(users(:orpheus))
    get review_ship_path(@ship)
    assert_response :success
    assert_select "form[action=?]", review_ship_decisions_path(@ship), 0
    assert_select ".review__panel", /Waiting on a reviewer/

    post review_ship_decisions_path(@ship), params: { review: { decision: "rejected", note_to_maker: "Looks fake to me." } }
    assert_response :unprocessable_entity
    assert @ship.reload.in_review?
  end

  test "nobody else can see it, or decide" do
    get review_root_path
    assert_response :not_found
    get review_ship_path(@ship)
    assert_response :not_found

    Rails.configuration.x.admin_slack_ids = []
    sign_in_as(users(:orpheus))
    get review_root_path
    assert_response :not_found
    post review_ship_decisions_path(@ship), params: { review: { decision: "rejected", note_to_maker: "Not a reviewer." } }
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
