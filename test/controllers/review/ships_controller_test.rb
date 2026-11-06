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
    assert_select ".admin__nav a[aria-current=page]", "Review"
    assert_select ".admin__nav a[href=?]", review_root_path(queue: "fraud"), "Fraud check"
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
      assert_select "input[type=radio][name='review[decision]']", 4
      assert_select "input[type=radio][name='review[hold]']", 2
      assert_select "input[type=radio][value=approved][checked]"
      assert_select "input[name='review[approved_hours]'][value='7.5'][max='7.5']"
    end

    post review_ship_decisions_path(@ship), params: { review: { decision: "approved", approved_hours: "6", justification: "short" } }
    assert_response :unprocessable_entity
    assert_select ".review__errors li", /Justification needs at least 30/
    assert_select ".review__errors li", /Deflation reason needs at least 10/
    assert_select "input[name='review[approved_hours]'][value='6.0']", 1, "what they typed stays"
    assert @ship.reload.in_review?

    @ship.update!(fraud_status: "good", fraud_score: 9)
    post review_ship_decisions_path(@ship), params: { review: { decision: "approved", approved_hours: "6", deflation_reason: "1.5h was another game",
                                                                justification: "Played it to 10 points; each frame really is a component." } }
    assert_redirected_to review_root_path
    assert_equal "Pong in Figma: approved. That's the whole queue.", flash[:notice]
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

  test "the page shows what was found, resyncs it, and dismisses a flag with why" do
    sign_in_as(users(:orpheus))
    get review_ship_path(@ship)
    assert_select "[data-evidence=pending]", /Gathering it/

    Github.stubbed = { "ana/pong" => { repo: Github::Repo.new(full_name: "ana/pong", created_at: Time.utc(2026, 10, 8), pushed_at: nil,
                                                              fork: false, parent: nil, stars: 0),
                                       commits: [ Github::Commit.new(sha: "abc1234", message: "paddles", author_name: "Ana", author_login: "ana",
                                                                     at: @ship.created_at - 1.hour, url: "https://github.com/ana/pong/commit/abc1234") ],
                                       readme: true } }
    link_hackatime(users(:ana), token: "token-heidi")
    ShipEvidence.build!(@ship.reload)
    get review_ship_path(@ship)
    assert_select ".review__evidence-block", /0 hrs tracked from Oct 6 to the ship/
    assert_select ".review__evidence-block", /1 commit since Oct 6\s+by ana \(1\)/
    assert_select ".review__commits a[href='https://github.com/ana/pong/commit/abc1234']", "paddles"
    assert_select ".review__days .review__day[data-level='0']", (@ship.created_at.in_time_zone(users(:ana).reload.time_zone).to_date - Program::HACKATIME_START).to_i + 1
    flag = @ship.flags.find_by!(kind: "few_commits")
    assert_select ".review__flag[data-severity=warn]", /Warning:\s*Only 1 commit since wrong tool started/

    patch review_ship_flag_path(@ship, flag), params: { dismiss_reason: "short" }
    assert_equal "Dismiss reason needs at least 10 characters: why it's fine", flash[:alert]
    patch review_ship_flag_path(@ship, flag), params: { dismiss_reason: "it's a one-file Figma export" }
    assert flag.reload.dismissed?
    follow_redirect!
    assert_select ".review__flag[data-severity=dismissed]", /1 dismissed flag.*Orpheus: it's a one-file Figma export/m

    assert_enqueued_with(job: ShipEvidenceJob) { post review_ship_evidence_path(@ship) }
    assert_redirected_to review_ship_path(@ship)
  ensure
    Github.stubbed = {}
  end

  test "the page shows Hackatime's call on their hours and their timelapses of it, and the maker's pages show neither" do
    before = [ Hackatime.stubbed_trust, Lapse.stubbed ]
    link_hackatime(users(:ana), token: "token-heidi")
    Hackatime.stubbed_trust = { "1002" => "yellow" }
    Lapse.stubbed = { "1002" => [ lapse_timelapse(id: "tl9", hackatime_project: "pong", name: "Pong, hour 2", seconds: 95 * 60),
                                  lapse_timelapse(id: "tl8", hackatime_project: "pong", name: "Pong, hour 1", blocker: "Shows their address",
                                                  recorded_at: Time.utc(2026, 10, 7, 20)) ] }
    ShipEvidence.build!(@ship.reload)

    sign_in_as(users(:orpheus))
    get review_ship_path(@ship)
    assert_select ".review__trust[data-trust=yellow]", /Hackatime has its doubts about them \(trust level yellow/
    assert_select ".review__flag[data-severity=warn]", /Hackatime has its doubts about them \(trust level yellow\)/
    assert_select ".review__subheading", /Timelapses on Lapse · 2 recordings/
    assert_select "[data-lapse=coverage]", /2.3 hrs recorded\s+of 0 hrs on Hackatime\s+to the ship/
    assert_select ".review__timelapses a[href='https://lapse.hackclub.com/timelapse/tl9']", "Pong, hour 2"
    assert_select ".review__timelapses", /pong · about 2 hours recorded · Oct 8, \d\d:00 · unlisted/
    assert_select ".review__timelapses video[src='https://lapse.hackclub.com/video/tl9.mp4']"
    assert_select ".review__timelapses", /Lapse withheld the video: Shows their address/
    assert_select ".review__timelapses video[src='https://lapse.hackclub.com/video/tl8.mp4']", 0

    sign_in_as(users(:ana))
    get project_path
    assert_response :success
    assert_no_match(/trust level|timelapse/i, response.body, "their own pages say nothing of either")
    get project_ship_path
    assert_no_match(/trust level|timelapse/i, response.body)
  ensure
    Hackatime.stubbed_trust, Lapse.stubbed = before
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

  test "fraud reviewers land in the fraud check, score it, and can't decide it" do
    users(:orpheus).update!(review_roles: [ "fraud" ])
    Rails.configuration.x.admin_slack_ids = []
    sign_in_as(users(:orpheus))
    get review_root_path
    assert_select "h1", "Fraud check"
    assert_equal [ "Fraud check" ], css_select(".admin__nav a").map(&:text)
    assert_select "tr##{dom_id(@ship)} a[href=?]", review_ship_path(@ship, queue: "fraud")

    get review_ship_path(@ship)
    assert_select "#review-decision", "Fraud check"
    assert_select "form[action=?]", review_ship_decisions_path(@ship), 0
    assert_select "form[action=?] input[type=radio][name='verdict[trust_score]']", review_ship_fraud_verdict_path(@ship), 10
    assert_equal "fraud", ReviewClaim.find_by(ship: @ship).queue

    post review_ship_decisions_path(@ship), params: { review: { decision: "rejected", note_to_maker: "Looks fake to me." } }
    assert_response :unprocessable_entity
    assert @ship.reload.in_review?

    post review_ship_fraud_verdict_path(@ship), params: { verdict: { trust_score: "9", justification: "short" } }
    assert_response :unprocessable_entity
    assert_select ".review__errors li", /Justification needs at least 10/

    post review_ship_fraud_verdict_path(@ship), params: { verdict: { trust_score: "9", justification: "Real heartbeats, real commits.", mark_sus: "1" } }
    assert_redirected_to review_root_path(queue: "fraud")
    assert_equal "Pong in Figma: passed the fraud check. That's the whole queue.", flash[:notice]
    assert_equal [ "sus", 9 ], [ @ship.reload.fraud_status, @ship.fraud_score ]

    get review_ship_path(@ship)
    assert_select ".review__call[data-decision=fraud_pass]", /Passed the fraud check.*Orpheus.*9\/10, marked sus.*Real heartbeats/m
  end

  test "reviewers never see the fraud check's score or note" do
    @ship.review_decisions.create!(queue: "fraud", decision: "fraud_pass", reviewer: users(:orpheus), trust_score: 6,
                                   justification: "Some hours look scripted.")
    @ship.update!(fraud_status: "sus", fraud_score: 6)
    heidi = User.create!(hca_id: "ident!heidi", first_name: "Heidi", review_roles: [ "reviewer" ])
    Rails.configuration.x.admin_slack_ids = []
    sign_in_as(heidi)
    get review_ship_path(@ship)
    assert_response :success
    assert_select ".review__call", 0
    assert_no_match(/scripted|6\/10|sus/, response.body)
    get review_ship_path(@ship, queue: "fraud")
    assert_response :not_found
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
