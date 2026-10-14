require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "its title reads like the pledge" do
    assert_equal "A rhythm game in Spreadsheet", projects(:orpheus).title
    assert_equal "Something cursed over SSH", Project.new(idea: "something cursed", tool: "ssh", tool_name: "SSH").title
  end

  test "code tools track with the Hackatime plugin, the rest with Lapse, and Other goes by its name" do
    assert_equal "lapse", projects(:orpheus).tracker
    assert_equal "hackatime", Project.new(tool: "ssh").tracker
    assert_equal "hackatime", Project.new(tool: "shaders").tracker
    { "Google Slides" => "lapse", "Discord" => "lapse", "Home Assistant" => "lapse", "a PDF" => "lapse",
      "CMake ONLY" => "hackatime", "pure CSS" => "hackatime", "Github Actions" => "hackatime", "git commits" => "hackatime",
      "C" => "hackatime", "brainf**k" => "hackatime" }.each do |name, tracker|
      assert_equal tracker, Project.new(tool: "other", tool_name: name).tracker, name
    end
    assert projects(:orpheus).lapse_tool?
  end

  test "build days run from the day wrong tool starts, one session of the pace a day, until the hours are in" do
    project = projects(:orpheus) # 45 min a day, signed before wrong tool starts

    with_hours_needed(10.0) do # a pick that takes 10 hours
      assert_equal 14, project.build_days.size
      assert_equal Date.new(2026, 10, 6), project.build_days.first
      assert_equal Date.new(2026, 10, 19), project.finish_on
    end
    assert_equal 14, project.build_days.size, "the Miyoo, one of the two we promised, is 10 hours as it comes"
  end

  test "signing after wrong tool starts counts from that day" do
    project = projects(:orpheus)
    project.signed_on = Date.new(2026, 10, 8)

    assert_equal Date.new(2026, 10, 8), project.build_days.first
  end

  test "building on weekends only counts Saturdays and Sundays" do
    project = projects(:orpheus)
    project.assign_attributes(build_time: "weekends", pace_minutes: 180)

    with_hours_needed(10.0) do
      assert_equal [ Date.new(2026, 10, 10), Date.new(2026, 10, 11), Date.new(2026, 10, 17), Date.new(2026, 10, 18) ], project.build_days
    end
  end

  test "setting up takes linking Hackatime; your project, a repo and a buddy can wait" do
    project = projects(:orpheus)
    assert_equal 0, project.required_steps_done
    assert project.step_locked?("hackatime_project")

    link_hackatime(project.user)
    project.hackatime_projects = [ "rhythm-game" ]
    assert project.tracking?
    assert_not project.step_locked?("hackatime_project")
    assert project.set_up?, "linking Hackatime is all setup needs"
    assert_equal 2, project.optional_steps_left

    project.assign_attributes(repo_later: true, buddy_skipped: true)
    assert_equal 0, project.optional_steps_left
    assert project.step_open?("repo"), "a repo put off till later can still be added"
    assert_not project.step_open?("slack"), "everyone's added to #wrong for them"
  end

  test "renaming it changes its title, and renaming it to nothing puts back your idea and tool" do
    project = projects(:orpheus)
    project.update!(name: "  Beat Sheet  ")
    assert_equal "Beat Sheet", project.title

    project.update!(name: " ")
    assert_nil project.name
    assert_equal "A rhythm game in Spreadsheet", project.title
  end

  test "a screenshot has to be an image, and not a huge one" do
    project = projects(:orpheus)
    project.screenshot.attach(io: file_fixture("notes.txt").open, filename: "notes.txt", content_type: "text/plain")
    assert_not project.valid?
    assert_equal [ "Screenshot should be a PNG, JPEG, WebP or GIF" ], project.errors.full_messages

    project.screenshot.attach(io: file_fixture("screenshot.png").open, filename: "screenshot.png", content_type: "image/png")
    assert project.valid?
  end

  test "the ticked Hackatime projects are the linked ones, and new ones have to be on Hackatime" do
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.available_hackatime_projects = Hackatime.projects(project.user)
    project.hackatime_project_names = [ "rhythm-game", "", "dotfiles", "rhythm-game" ]
    assert project.valid?
    assert_equal [ "rhythm-game", "dotfiles" ], project.hackatime_projects
    project.save!

    project.hackatime_project_names = [ "dotfiles", "not-mine" ]
    assert_not project.valid?
    assert_equal [ "Hackatime projects don't include not-mine on Hackatime" ], project.errors.full_messages

    project.available_hackatime_projects = []
    project.hackatime_project_names = [ "dotfiles" ]
    assert project.valid?, "ones already linked stay linkable, even once Hackatime stops listing them"

    project.hackatime_project_names = []
    assert_not project.valid?

    link_hackatime(project.user)
    project.hackatime_projects = [ "rhythm-game" ]
    assert project.step_done?("hackatime_project")
    assert project.step_open?("hackatime_project")
  end

  test "only takes the answers onboarding offers" do
    project = projects(:orpheus)
    project.assign_attributes(tool: "notepad", prize: "switch", pace_minutes: 5, build_time: "never",
                              repo_url: "my repo")

    assert_not project.valid?
    assert_equal %i[tool prize pace_minutes build_time repo_url].sort, project.errors.attribute_names.sort
  end

  test "your console's colour is one it comes in, or the first one, and goes with the console" do
    project = projects(:orpheus)
    assert_equal "Miyoo Mini Plus in gray", project.prize_name
    assert_equal "grey", project.console_color.id

    project.prize_color = "purple"
    assert project.valid?
    assert_equal "Miyoo Mini Plus in purple", project.prize_name

    project.prize_color = "plaid"
    assert_not project.valid?
    assert_equal [ :prize_color ], project.errors.attribute_names

    # Grey's a colour the SP comes in too, so it stays; teal isn't one the Miyoo comes in.
    project.update!(prize: "rg35xxsp", prize_color: "grey")
    assert_equal "grey", project.prize_color
    project.update!(prize: "miyoo", prize_color: "teal")
    assert_nil project.prize_color
    assert_equal "Gray", project.console_color.name

    assert_empty project.orders, "nothing bought"
  end

  test "your pick's extras are ones its maker offers, price it as the maker does, and set the hours it takes" do
    project = projects(:orpheus)
    assert_equal({ "storage" => "64" }, project.prize_choices)
    assert_equal 58.99, project.prize_price
    assert_equal 10.0, project.hours_needed
    assert_equal "Miyoo Mini Plus in gray, 64GB", project.prize_configuration
    assert_not project.afford?
    assert project.afford?(10)
    assert_equal 14, project.build_days.size # 10 hours at 45 minutes

    project.prize_options = { storage: "none" }
    assert project.valid?
    assert_equal 53.99, project.prize_price
    assert_equal 10.0, project.hours_needed # a cheaper choice takes nothing off a promised prize
    assert_equal "Miyoo Mini Plus in gray", project.prize_configuration

    project.prize_options = { storage: "512", bag: "yes" } # Miyoo sells no bags
    assert_not project.valid?
    assert_equal [ :prize_options ], project.errors.attribute_names

    # A 64 GB card is something the SP sells too, so it carries over; "no card" isn't, so it wouldn't.
    project.update!(prize_options: { storage: "64" })
    project.update!(prize: "rg35xxsp")
    assert_equal({ "storage" => "64" }, project.prize_options)
    # And a bigger card and a bag on the SP carry over to the RG34XX SP, which Anbernic sells them for too.
    project.update!(prize_options: { storage: "128", bag: "yes" })
    project.update!(prize: "rg34xxsp")
    assert_equal({ "storage" => "128", "bag" => "yes" }, project.prize_options)
    assert_equal 107.98, project.prize_price

    assert_equal 25, project.hours_needed # not a promised prize: 10 + 57.98 / 4, up to a whole hour
  end
end

class ProjectDeadlineTest < ActiveSupport::TestCase
  test "the deadline is wrong tool's last day, a week on once an extension's approved" do
    project = projects(:orpheus)
    assert_equal Date.new(2026, 10, 20), project.deadline

    extension = project.create_extension!(reason: "exams")
    assert_equal Date.new(2026, 10, 20), project.reload.deadline, "asking alone moves nothing"
    extension.update!(status: "denied")
    assert_equal Date.new(2026, 10, 20), project.reload.deadline

    extension.update!(status: "approved")
    assert_equal Date.new(2026, 10, 27), project.reload.deadline
    assert_equal Date.new(2026, 10, 6)..Date.new(2026, 10, 27), project.program_dates
  end

  test "ship closes at the end of the deadline where you are, plus two quiet days" do
    project = projects(:orpheus)
    assert_equal Time.utc(2026, 10, 22, 23, 59, 59), project.ship_cutoff.change(usec: 0), "UTC until they've said where they are"

    users(:orpheus).update!(timezone: "America/New_York")
    assert project.reload.may_ship?(now: Time.utc(2026, 10, 23, 2))
    assert_not project.may_ship?(now: Time.utc(2026, 10, 23, 4))

    project.create_extension!(reason: "exams", status: "approved")
    assert project.reload.may_ship?(now: Time.utc(2026, 10, 30, 2))
    assert_not project.may_ship?(now: Time.utc(2026, 10, 30, 4))
  end

  test "you can ask for more time once, while set up and unshipped, up to the deadline where you are" do
    project = projects(:orpheus)
    assert_not project.extension_requestable?, "not set up yet"

    link_hackatime(users(:orpheus))
    project.update!(hackatime_projects: [ "rhythm-game" ], repo_later: true, buddy_skipped: true)
    assert project.reload.extension_requestable?(now: Time.utc(2026, 10, 12, 12))

    noon = Time.utc(2026, 10, 20, 12) # Oct 21 already in Kiritimati, still Oct 20 in Pago Pago
    users(:orpheus).update!(timezone: "Pacific/Kiritimati")
    assert_not project.reload.extension_requestable?(now: noon)
    users(:orpheus).update!(timezone: "Pacific/Pago_Pago")
    assert project.reload.extension_requestable?(now: noon)
    assert_not project.extension_requestable?(now: Time.utc(2026, 10, 21, 12)), "not through the grace days"

    project.ships.create!(title: "Beat Sheet", description: "A rhythm game where every cell is a drum pad, built in Sheets.",
                          repo_url: "https://github.com/orpheus/beat-sheet", demo_url: "https://beat.sheet", status: "approved",
                          screenshot: { io: file_fixture("screenshot.png").open, filename: "screenshot.png", content_type: "image/png" },
                          screenshot_shows_game: true)
    assert_not project.reload.extension_requestable?(now: noon), "shipped"
    project.ships.destroy_all

    project.create_extension!(reason: "exams")
    assert_not project.reload.extension_requestable?(now: noon), "asked already"
  end
end
