require "test_helper"

class GalleryControllerTest < ActionDispatch::IntegrationTest
  def ship!(project, title, status: "approved", **attributes)
    project.ships.create!(title:, description: "#{title}: two paddles, one ball, and every frame is drawn by hand.",
                          repo_url: "https://github.com/#{project.user.slack_display_name}/game",
                          demo_url: "https://example.com/#{title.parameterize}", hackatime_projects: [ "game" ], hours: 7.5,
                          screenshot: screenshot_upload, screenshot_shows_game: true, **attributes)
      .tap { |ship| ship.update!(status:, decided_at: Time.current) unless status == "in_review" }
  end

  test "with nothing shipped, anyone sees it's empty" do
    get gallery_path

    assert_response :success
    assert_select "h1", "Gallery"
    assert_select ".leaderboard__note", /Nothing's shipped yet/
    assert_select ".gallery__card", false
    assert_select ".sheet-tab[aria-current=page]", /Gallery/
  end

  test "anyone sees each project's latest ship, whatever review made of it, by the name everyone sees" do
    ship!(projects(:ana), "Old Pong", status: "rejected")
    pong = ship!(projects(:ana), "Pong in Figma", status: "approved", approved_hours: 6)
    rhythm = ship!(projects(:orpheus), "Rhythm sheet", status: "in_review")

    get gallery_path

    assert_response :success
    assert_select ".gallery__card", 2, "one card a project: its latest ship"
    assert_select ".gallery__title", { text: "Old Pong", count: 0 }
    assert_select "##{dom_id(pong)}" do
      assert_select ".gallery__title", "Pong in Figma"
      assert_select ".gallery__status[data-status=approved]", "Approved"
      assert_select ".gallery__tool", /in Figma · 6 hrs/
      assert_select ".gallery__maker", /pixelana/
      assert_select "a.gallery__link--play[href='https://example.com/pong-in-figma']", "Play"
      assert_select "a.gallery__link[href='https://github.com/pixelana/game']", "Code"
    end
    assert_select "##{dom_id(rhythm)} .gallery__status", "In review"
    assert_no_match(/Ana Lovelace|ana@hackclub/, response.body)
  end

  test "not approved, it's still there, saying so" do
    ship!(projects(:ana), "Pong in Figma", status: "rejected")

    get gallery_path

    assert_select ".gallery__card", 1
    assert_select ".gallery__status[data-status=rejected]", "Not approved"
  end

  test "filtered by the wrong tool, and your own game is yours" do
    ship!(projects(:ana), "Pong in Figma")
    rhythm = ship!(projects(:orpheus), "Rhythm sheet")

    get gallery_path(tool: "spreadsheet")
    assert_select ".gallery__card", 1
    assert_select ".gallery__title", "Rhythm sheet"
    assert_select ".leaderboard__sort[aria-current=page]", "Spreadsheets"

    sign_in_as(users(:orpheus))
    get gallery_path
    assert_select ".gallery__card", 2
    assert_select "##{dom_id(rhythm)}[data-yours] .gallery__maker", /You/

    get gallery_path(tool: "nonsense")
    assert_select ".gallery__card", 2, "a tool nobody shipped in shows everything"
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
