require "test_helper"

class ShipTest < ActiveSupport::TestCase
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

  test "deciding is an admin's call, made once, and the ship that stands is each project's newest" do
    first = ship_now(hours: 3)
    assert_not first.decide!("maybe", by: users(:ana))
    assert first.decide!("rejected", by: users(:ana))
    assert first.rejected?
    assert_equal users(:ana), first.decided_by
    assert_not first.decide!("approved", by: users(:ana)), "decided already"
    assert first.reload.rejected?

    second = ship_now(hours: 5)
    assert_equal [ second ], Ship.latest_per_project.to_a
    assert_equal 5, Ship.latest_per_project.sum(:hours)
    assert_equal [ first ], Ship.where(created_at: ..first.created_at).latest_per_project.to_a, "as of a time, the newest then"
  end

  test "approving grants the hours it took to spend, or fewer if the admin says, and the most of any approved ship counts" do
    assert_equal 0, @project.hours_approved
    first = ship_now(hours: 6)
    first.decide!("approved", by: users(:ana), hours: "99")
    assert_equal 6, first.approved_hours, "never more than it took"
    assert_equal 6, @project.reload.hours_approved

    rejected = ship_now(hours: 9)
    rejected.decide!("rejected", by: users(:ana), hours: "9")
    assert_nil rejected.approved_hours
    assert_equal 6, @project.reload.hours_approved

    second = ship_now(hours: 11)
    second.decide!("approved", by: users(:ana), hours: "10.5")
    assert_equal 10.5, second.approved_hours
    assert_equal 10.5, @project.reload.hours_approved, "each ship counts every hour up to it, so the most, not the sum"

    ship_now(hours: 2).decide!("approved", by: users(:ana), hours: "-4")
    assert_equal 10.5, @project.reload.hours_approved
  end

  private
    def ship_now(hours:)
      @project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every beat is a cell lighting up in time.",
                             repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://example.com/beat",
                             hours:, screenshot: fixture_upload, screenshot_shows_game: true)
    end

    def fixture_upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end
end
