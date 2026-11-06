require "test_helper"

class ShipEvidenceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:orpheus)
    @user.update!(timezone: "America/New_York")
    link_hackatime(@user)
    @project = projects(:orpheus)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
    @before = [ Github.stubbed, DemoProbe.stubbed, Hackatime.stubbed_spans, Hackatime.stubbed_trust, Lapse.stubbed ]
  end

  teardown { Github.stubbed, DemoProbe.stubbed, Hackatime.stubbed_spans, Hackatime.stubbed_trust, Lapse.stubbed = @before }

  test "shipping asks for it, and it gathers Hackatime, the repo and its commits, and the demo, all from before the ship" do
    Hackatime.stubbed_trust = { "1001" => "green" }
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
    assert_equal({ "hackatime" => "ok", "hackatime_trust" => "ok", "github" => "ok", "demo" => "ok", "lapse" => "ok" }, evidence.sources)
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
    assert_equal %w[few_commits lapse_missing], ship.flags.pluck(:kind).sort, "2 commits, and a spreadsheet game with no Lapse recording"
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
                   [ "demo_unreachable", "warn", "The demo link answers 404" ],
                   [ "lapse_missing", "warn", "Built on Lapse, but no recordings of rhythm-game before the ship" ] ].sort, flags.sort

    Github.stubbed = { "orpheus/beat-sheet" => {
      repo: Github::Repo.new(full_name: "orpheus/beat-sheet", created_at: Time.utc(2026, 8, 1), pushed_at: nil, fork: true,
                             parent: "someone/beats", stars: 0),
      commits: [ commit("c1", Time.utc(2026, 10, 7, 9), "start") ] } }
    ship.flags.find_by(kind: "marathon").dismiss!(by: users(:ana), reason: "a game jam day, they said")
    ShipEvidence.build!(ship)
    assert_equal %w[demo_unreachable duplicate few_commits fork lapse_missing marathon no_readme old_repo time_after_commits], ship.flags.pluck(:kind).sort,
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
    assert_equal [ [ "external_repo", "warn" ], [ "hackatime_unread", "warn" ], [ "lapse_missing", "warn" ] ],
                 ship.flags.order(:kind).pluck(:kind, :severity), "their Lapse is still read: it needs only their Hackatime ID"
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

    assert_equal "red", ship.evidence.data["trust"]["trust_level"]
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
    trust = ship.evidence.data["trust"]
    assert_equal "ok", ship.evidence.sources["hackatime"]
    assert_equal 90 * 60, time["tracked_seconds"]
    assert_equal [ "red", true ], [ trust["trust_level"], trust["trust_stale"] ]
    assert_equal "couldn't be reached with their token, since there's no admin key here (timed out)", ship.evidence.sources["hackatime_trust"],
                 "and why, for the reviewer"
    assert_equal "danger", ship.flags.find_by(kind: "hackatime_trust").severity
  end

  test "their token having stopped working loses their hours, but not what Hackatime makes of them" do
    Hackatime.stubbed_trust = { "1001" => "red" }
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    Hackatime.singleton_class.alias_method(:heartbeat_spans_without_test, :heartbeat_spans)
    Hackatime.define_singleton_method(:heartbeat_spans) { |*, **| raise Hackatime::Expired }
    begin
      ShipEvidence.build!(ship)
    ensure
      Hackatime.singleton_class.alias_method(:heartbeat_spans, :heartbeat_spans_without_test)
      Hackatime.singleton_class.remove_method(:heartbeat_spans_without_test)
    end

    assert_equal "Hackatime stopped accepting their token", ship.evidence.sources["hackatime"]
    assert_nil ship.evidence.data["hackatime"]
    assert_equal "red", ship.evidence.data["trust"]["trust_level"]
    assert_equal "danger", ship.flags.find_by(kind: "hackatime_trust").severity
    assert ship.flags.find_by(kind: "hackatime_unread"), "and that the hours couldn't be read"
  end

  test "resyncing the waiting ships gathers each in review again, and leaves decided ones alone" do
    waiting = ship_now
    decided = ship_now(repo_url: "https://github.com/orpheus/old")
    decided.update_columns(status: "approved")
    ShipEvidence.build!(waiting)
    clear_enqueued_jobs

    assert_equal [ waiting ], ShipEvidence.request_waiting
    assert_enqueued_jobs 1, only: ShipEvidenceJob
    assert waiting.evidence.reload.pending?
  end

  test "Lapse: the maker's timelapses of the ship's Hackatime projects, newest first, and none of anyone else's" do
    Lapse.stubbed = {
      "1001" => [ lapse_timelapse(id: "tl1", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 7, 18)),
                  lapse_timelapse(id: "tl2", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 9, 18)),
                  lapse_timelapse(id: "tl3", hackatime_project: "dotfiles") ],
      "1002" => [ lapse_timelapse(id: "tl4", hackatime_project: "rhythm-game") ]
    }

    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)

    lapse = ship.evidence.data["lapse"]
    assert_equal %w[tl2 tl1], lapse["timelapses"].map { |timelapse| timelapse["id"] }, "theirs, for this ship's project, newest first"
    assert_equal "https://lapse.hackclub.com/timelapse/tl2", lapse["timelapses"].first["page_url"]
    assert_nil lapse["since"], "the project's first ship: every recording counts"
    assert_equal 0, lapse["earlier"]
    assert_equal "ok", ship.evidence.sources["lapse"]
  end

  test "Lapse on a later ship: only what was made since the last approved one, and how much of Hackatime's time it covers" do
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Time.utc(2026, 10, 7, 14), 60), hackatime_span(Time.utc(2026, 10, 12, 14), 90),
                                            hackatime_span(Time.utc(2026, 10, 13, 14), 30) ] }
    Lapse.stubbed = { "1001" => [
      lapse_timelapse(id: "first", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 7, 15), seconds: 3600),
      lapse_timelapse(id: "second", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 12, 16), seconds: 80 * 60),
      lapse_timelapse(id: "late", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 16, 9), seconds: 25 * 60)
    ] }
    travel_to(Time.utc(2026, 10, 8)) { ship_now }.update_columns(status: "approved")
    asked_again = travel_to(Time.utc(2026, 10, 9)) { ship_now }
    asked_again.update_columns(status: "changes_requested")

    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)

    lapse = ship.evidence.data["lapse"]
    assert_equal %w[late second], lapse["timelapses"].map { |timelapse| timelapse["id"] },
                 "since the approved ship, changes asked for or not; the one before it went with that ship"
    assert_equal Time.utc(2026, 10, 8).iso8601, lapse["since"]
    assert_equal 1, lapse["earlier"]
    assert_equal [ true, false ], lapse["timelapses"].map { |timelapse| timelapse["after_ship"] }, "published once it was done"
    assert_equal 80 * 60, lapse["seconds"], "only what was recorded by the ship"
    assert_equal 120 * 60, lapse["hackatime_seconds"], "Hackatime's time over the same stretch"
  end

  test "Lapse not being set up here leaves it out, Lapse being down only says so, and no Hackatime ID is not linked" do
    Lapse.stubbed = nil
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)
    assert_not ship.evidence.sources.key?("lapse")
    assert_nil ship.evidence.data["lapse"]

    Lapse.stubbed = {}
    with_lapse_down { ShipEvidence.build!(ship) }
    assert_equal "couldn't be reached (timed out)", ship.evidence.reload.sources["lapse"]
    assert ship.evidence.built?, "a review never waits on Lapse"

    @user.update!(hackatime_uid: nil, hackatime_access_token: nil)
    ShipEvidence.build!(ship.reload)
    assert_equal "Hackatime isn't linked", ship.evidence.reload.sources["lapse"]
    assert_equal [ "hackatime_unread" ], ship.flags.where("kind LIKE 'hackatime%' OR kind LIKE 'lapse%'").pluck(:kind),
                 "said once, by Hackatime"
  end

  test "Lapse flags, for a project built on Lapse: none recorded, far less recorded than Hackatime has, or Lapse unread" do
    Hackatime.stubbed_spans = { "1001" => [ hackatime_span(Time.utc(2026, 10, 7, 14), 180) ] }
    Lapse.stubbed = { "1001" => [ lapse_timelapse(id: "tl1", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 7, 17), seconds: 60 * 60) ] }
    ship = travel_to(Time.utc(2026, 10, 15)) { ship_now }
    ShipEvidence.build!(ship)
    flag = ship.flags.find_by(kind: "lapse_short")
    assert_equal "Lapse recordings cover only 1h of the 3h on Hackatime before the ship", flag.title
    assert_equal "warn", flag.severity

    Lapse.stubbed["1001"] << lapse_timelapse(id: "tl2", hackatime_project: "rhythm-game", recorded_at: Time.utc(2026, 10, 7, 18), seconds: 60 * 60)
    ShipEvidence.build!(ship)
    assert_empty ship.flags.where(kind: %w[lapse_short lapse_missing]), "2h of 3h is close enough"

    with_lapse_down { ShipEvidence.build!(ship) }
    assert_equal "Lapse couldn't be read: couldn't be reached (timed out)", ship.flags.find_by(kind: "lapse_unread").title

    @project.update_columns(tool: "shaders")
    with_lapse_down { ShipEvidence.build!(ship.reload) }
    Lapse.stubbed = {}
    ShipEvidence.build!(ship.reload)
    assert_empty ship.flags.where("kind LIKE 'lapse%'"), "a code tool records on Lapse only if it likes"
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
