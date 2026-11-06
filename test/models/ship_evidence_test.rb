require "test_helper"

class ShipEvidenceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    link_hackatime(@user)
    @project = projects(:orpheus)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    @before = [ Github.stubbed, DemoProbe.stubbed, Hackatime.stubbed_spans, Hackatime.stubbed_trust ]
  end

  teardown { Github.stubbed, DemoProbe.stubbed, Hackatime.stubbed_spans, Hackatime.stubbed_trust = @before }

  test "shipping asks for it, and it gathers Hackatime, the repo and its commits, and the demo, all from before the ship" do
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Time.utc(2026, 10, 7, 14), 90), hackatime_span(Time.utc(2026, 10, 9, 1), 30),
                                            hackatime_span(Time.utc(2026, 10, 20, 12), 60) ] }
    Github.stubbed = { "orpheus/beat-sheet" => {
      repo: Github::Repo.new(full_name: "orpheus/beat-sheet", created_at: Time.utc(2026, 10, 7), pushed_at: Time.utc(2026, 10, 10),
                             fork: false, parent: nil, stars: 2),
      commits: [ commit("c3", Time.utc(2026, 10, 25), "after the ship"), commit("c2", Time.utc(2026, 10, 9, 1, 45), "levels"),
                 commit("c1", Time.utc(2026, 10, 7, 15), "first beat"), commit("c0", Time.utc(2026, 9, 1), "before wrong tool") ],
      readme: true } }

    ship = nil
    travel_to(Time.utc(2026, 10, 15, 12)) do
      ship = ship_now
      assert_enqueued_with(job: ShipEvidenceJob, args: [ ship ])
      assert ship.reload.evidence.pending?
      perform_enqueued_jobs(only: ShipEvidenceJob)
    end

    evidence = ship.reload.evidence
    assert evidence.built?
    assert_equal({ "hackatime" => "ok", "github" => "ok", "demo" => "ok" }, evidence.sources)
    time = evidence.data["hackatime"]
    assert_equal 120 * 60, time["tracked_seconds"], "not the session after the ship"
    assert_equal({ "2026-10-07" => 90 * 60, "2026-10-08" => 30 * 60 }, time["days"], "9pm on the 8th in New York")
    assert_equal [ 90 * 60 ], time["long_sessions"].map { |session| session["seconds"] }
    assert_equal 0, time["after_last_commit_seconds"], "the last session ended at 9:30pm on the 8th, before the last commit"
    repo = evidence.data["repo"]
    assert_equal %w[c2 c1], repo["commits"].map { |commit| commit["sha"] }, "only in wrong tool, before the ship"
    assert_equal({ "orpheus" => 2 }, repo["commit_authors"])
    assert repo["readme"]
    assert evidence.data["demo"]["reachable"]
    assert_equal [ "few_commits" ], ship.flags.pluck(:kind), "2 commits"
  end

  test "flags: marathons, time nobody committed, a missing repo, a broken demo, and the same links as another project" do
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Time.utc(2026, 10, 7, 8), 10 * 60) ] }
    DemoProbe.stubbed = { "https://example.com/beat" => 404 }
    projects(:ana).ships.create!(title: "Pong in Figma", description: "Two paddles, one ball, and every frame is a Figma component.",
                                 repo_url: "https://github.com/Orpheus/beat-sheet.git", demo_url: "https://example.com/pong", hours: 2,
                                 screenshot: upload, screenshot_shows_game: true)

    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)
    flags = ship.flags.by_severity.map { |flag| [ flag.kind, flag.severity, flag.title ] }
    assert_equal [ [ "marathon", "danger", "A session of 6h+ without a break (longest 10h)" ],
                   [ "repo_missing", "danger", "The repo isn't public on GitHub (orpheus/beat-sheet)" ],
                   [ "duplicate", "danger", "Another project shipped the same repo link: Pong in Figma" ],
                   [ "demo_unreachable", "warn", "The demo link answers 404" ] ].sort, flags.sort

    Github.stubbed = { "orpheus/beat-sheet" => {
      repo: Github::Repo.new(full_name: "orpheus/beat-sheet", created_at: Time.utc(2026, 8, 1), pushed_at: nil, fork: true,
                             parent: "someone/beats", stars: 0),
      commits: [ commit("c1", Time.utc(2026, 10, 7, 9), "start") ] } }
    ship.flags.find_by(kind: "marathon").dismiss!(by: users(:ana), reason: "a game jam day, they said")
    ShipEvidence.build!(ship)
    assert_equal %w[demo_unreachable duplicate few_commits fork marathon no_readme old_repo time_after_commits], ship.flags.pluck(:kind).sort,
                 "the repo's there now; the dismissed marathon stays"
    assert ship.flags.find_by(kind: "marathon").dismissed?
    assert_equal "9h tracked after the last commit", ship.flags.find_by(kind: "time_after_commits").title
    assert_equal "The repo's older than wrong tool (made Aug 1, 2026)", ship.flags.find_by(kind: "old_repo").title
  end

  test "a repo off GitHub, and Hackatime that can't be read, are warnings" do
    @user.update!(hackatime_access_token: nil)
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now(repo_url: "https://gitlab.com/orpheus/beat-sheet") }
    ShipEvidence.build!(ship.reload)
    assert_equal "Hackatime isn't linked", ship.evidence.sources["hackatime"]
    assert_equal [ [ "external_repo", "warn" ], [ "hackatime_unread", "warn" ] ], ship.flags.order(:kind).pluck(:kind, :severity)
  end

  test "a red flag holds up approving, until someone dismisses it with why" do
    users(:ana).update!(review_roles: [ "reviewer" ])
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)
    approve = -> { ShipReview.decide(ship, by: users(:ana), decision: "approved", approved_hours: ship.hours.to_s, justification: "Played it through; the beats sync in formulas.") }

    assert_equal [ "Dismiss the red flags first, with why: The repo isn't public on GitHub (orpheus/beat-sheet)" ], approve.().errors.full_messages
    assert ShipReview.decide(ship, by: users(:ana), decision: "changes_requested", note_to_maker: "Make the repo public, please.").persisted?,
           "asking for changes doesn't wait on flags"

    ship = travel_to(Time.utc(2026, 10, 16)) { ship_now }
    ShipEvidence.build!(ship)
    flag = ship.flags.find_by(kind: "repo_missing")
    assert_not flag.dismiss!(by: users(:ana), reason: "fine")
    assert flag.reload.dismiss!(by: users(:ana), reason: "public now, I checked by hand")
    assert approve.().persisted?
  end

  test "what Hackatime makes of their hours is gathered, kept on them, and flagged: red holds up approving, yellow warns" do
    Hackatime.stubbed_trust = { "1001" => "red" }
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)

    assert_equal "red", ship.evidence.data["hackatime"]["trust_level"]
    assert_equal "red", @user.reload.hackatime_trust_level
    assert @user.hackatime_trust_checked_at.present?
    assert @user.hackatime_untrusted?
    flag = ship.flags.find_by(kind: "hackatime_trust")
    assert_equal [ "danger", "Hackatime doesn't trust their hours (trust level red)" ], [ flag.severity, flag.title ]

    Hackatime.stubbed_trust = { "1001" => "yellow" }
    ShipEvidence.build!(ship)
    assert_equal [ "warn", "Hackatime has its doubts about them (trust level yellow)" ],
                 ship.flags.find_by(kind: "hackatime_trust").then { |one| [ one.severity, one.title ] }
    assert @user.reload.hackatime_suspect?

    Hackatime.stubbed_trust = { "1001" => "green" }
    ShipEvidence.build!(ship)
    assert_nil ship.flags.find_by(kind: "hackatime_trust"), "Hackatime trusting them isn't worth saying"
    assert_equal "green", @user.reload.hackatime_trust_level
  end

  test "Hackatime not saying what it makes of their hours leaves the hours standing, with the last call it made" do
    Hackatime.stubbed_trust = { "1001" => "red" }
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Time.utc(2026, 10, 7, 14), 90) ] }
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)

    with_hackatime_trust_down { ShipEvidence.build!(ship) }
    time = ship.evidence.reload.data["hackatime"]
    assert_equal "ok", ship.evidence.sources["hackatime"]
    assert_equal 90 * 60, time["tracked_seconds"]
    assert_equal [ "red", true ], [ time["trust_level"], time["trust_stale"] ]
    assert_equal "danger", ship.flags.find_by(kind: "hackatime_trust").severity
  end

  test "the demo check never asks a private network" do
    DemoProbe.stubbed = nil
    %w[http://127.0.0.1/ http://localhost:3000/ http://10.0.0.5/ http://169.254.169.254/latest/meta-data http://[::1]/].each do |url|
      result = DemoProbe.check(url)
      assert_not result.reachable?, url
      assert_match(/private network|doesn't resolve/, result.error, url)
    end
    assert_equal "isn't a web link", DemoProbe.check("file:///etc/passwd").error
  ensure
    DemoProbe.stubbed = {}
  end

  private
    def ship_now(repo_url: "https://github.com/orpheus/beat-sheet")
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url:, demo_url: "https://example.com/beat", hackatime_projects: [ "rhythm-game" ], hours: 2,
                             screenshot: upload, screenshot_shows_game: true)
    end

    def commit(sha, at, message)
      Github::Commit.new(sha:, message:, author_name: "Orpheus", author_login: "orpheus", at:, url: "https://github.com/orpheus/beat-sheet/commit/#{sha}")
    end

    def upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end
end
