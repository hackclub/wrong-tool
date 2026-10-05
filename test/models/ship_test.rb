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

  private
    def fixture_upload
      Rack::Test::UploadedFile.new(file_fixture("screenshot.png"), "image/png")
    end
end
