require "test_helper"

class ShipTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = projects(:orpheus)
    link_hackatime(@project.user)
    @project.update!(hackatime_projects: [ "rhythm-game" ])
  end

  test "shipping keeps what you submitted, and makes it your project's name and repo" do
    ship = @project.ship!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                          repo_url: "github.com/orpheus/beat-sheet", demo_url: "https://docs.google.com/spreadsheets/d/beat",
                          screenshot: fixture_upload, screenshot_shows_game: "1")

    assert ship.persisted?
    assert ship.in_review?
    assert_equal [ "https://github.com/orpheus/beat-sheet", [ "rhythm-game" ] ], [ ship.repo_url, ship.hackatime_projects ]
    assert ship.screenshot.attached?
    assert_equal [ "Beat Sheet", "https://github.com/orpheus/beat-sheet" ], [ @project.reload.title, @project.repo_url ]
    assert @project.screenshot.attached?, "the screenshot you shipped with is your project's too"
    assert_equal ship, @project.ship_in_review
    assert_not @project.shipped?, "not shipped until it's approved"

    ship.update!(status: "approved")
    assert @project.reload.shipped?
  end

  test "a ship needs a title, a real description, both links, a screenshot and the check that it's real" do
    ship = @project.ship!(title: " ", description: "too short", repo_url: "", demo_url: "", screenshot_shows_game: "0")

    assert_not ship.persisted?
    assert_equal [ "Title can't be blank", "Description needs at least 40 characters", "Repo url should be a link",
                   "Demo url should be a link", "Screenshot is needed", "Screenshot shows game has to show the game running, not a mockup" ],
                 ship.errors.full_messages
    assert_nil @project.reload.name
  end

  test "a ship uses the screenshot your project already has" do
    @project.screenshot.attach(fixture_upload)
    ship = @project.ship!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                          repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                          screenshot_shows_game: "1")

    assert ship.persisted?
    assert_equal @project.screenshot.blob, ship.screenshot.blob
  end

  test "the ship that stands is each project's newest" do
    first = ship_now(hours: 3)
    first.update!(status: "changes_requested")
    second = ship_now(hours: 5)
    assert_equal [ second ], Ship.latest_per_project.to_a
    assert_equal 5, Ship.latest_per_project.sum(:hours)
    assert_equal [ first ], Ship.where(created_at: ..first.created_at).latest_per_project.to_a, "as of a time, the newest then"
    assert_equal second, @project.reload.latest_ship
  end

  test "the reminder DMs everyone who hasn't shipped, asked for changes counts, and a dry run sends nothing" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("ships:remind")
    ship_now(hours: 2)
    projects(:ana).ships.create!(title: "Pong in Figma", description: "Two paddles, one ball, and every frame is a Figma component.",
                                 repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours: 1,
                                 screenshot: fixture_upload, screenshot_shows_game: true).update!(status: "changes_requested")

    with_env("DRY_RUN" => "1") { capture_io { Rake::Task["ships:remind"].execute } }
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }

    capture_io { Rake::Task["ships:remind"].execute }
    dms = enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
    assert_equal [ "U0ANA" ], dms.map { |job| job[:args].first }
    assert_equal "wrong tool ends Oct 27, and *Pong in Figma* hasn't shipped yet. If it's playable, ship it, finished or not.\n" \
                 ":clippy-hopeful: clippy is holding the door open for you. :blob-wiggle:", dms.first[:args].second
    assert_equal [ "Ship it", "https://wrong.hackclub.com/ship" ], dms.first[:args].third["link"]
  end

  test "last call DMs everyone who never shipped with an hour or more, once, and a dry run sends nothing" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("ships:last_call")
    ship_now(hours: 2) # in review: not owed
    ana = projects(:ana)
    link_hackatime(ana.user, token: "token-heidi")
    ana.update!(hackatime_projects: [ "heidis-game" ])
    ana.ships.create!(title: "Pong in Figma", description: "Two paddles, one ball, and every frame is a Figma component.",
                      repo_url: "https://example.com/repo", demo_url: "https://example.com/demo", hours: 1,
                      screenshot: fixture_upload, screenshot_shows_game: true).update!(status: "changes_requested")
    ana.user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: 2 * 3600)

    with_env("DRY_RUN" => "1") { capture_io { Rake::Task["ships:last_call"].execute } }
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }

    capture_io { Rake::Task["ships:last_call"].execute }
    dms = enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
    assert_equal [ "U0ANA" ], dms.map { |job| job[:args].first }
    assert_equal "Shipping's open again for anyone who didn't make it. *Pong in Figma* can ship until the end of Nov 5, " \
                 "finished or not. If it plays, ship it.\n:clippy-hopeful: clippy propped the door back open for you. :blob-wiggle:",
                 dms.first[:args].second
    assert_not_nil ana.reload.last_call_dmed_at

    clear_enqueued_jobs
    capture_io { Rake::Task["ships:last_call"].execute }
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }, "once"
  end

  test "last call skips anyone under an hour" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("ships:last_call")
    @project.user.streak_activities.create!(activity_date: Program::DATES.begin, coded_seconds: 30 * 60)

    capture_io { Rake::Task["ships:last_call"].execute }
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
  end

  private
    def with_env(vars)
      originals = vars.keys.index_with { |key| ENV[key] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      originals.each { |key, value| ENV[key] = value }
    end

    def ship_now(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: fixture_upload, screenshot_shows_game: true)
    end

    def fixture_upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end
end
