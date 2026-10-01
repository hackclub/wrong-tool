require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "its title reads like the pledge" do
    assert_equal "A rhythm game in Spreadsheet", projects(:orpheus).title
    assert_equal "Something cursed over SSH", Project.new(idea: "something cursed", tool: "ssh", tool_name: "SSH").title
  end

  test "build days run from the day wrong tool starts, one session of the pace a day, until the hours are in" do
    project = projects(:orpheus) # 45 min a day, signed before wrong tool starts

    assert_equal 14, project.build_days.size
    assert_equal Date.new(2026, 10, 2), project.build_days.first
    assert_equal Date.new(2026, 10, 15), project.finish_on
  end

  test "signing after wrong tool starts counts from that day" do
    project = projects(:orpheus)
    project.signed_on = Date.new(2026, 10, 5)

    assert_equal Date.new(2026, 10, 5), project.build_days.first
  end

  test "building on weekends only counts Saturdays and Sundays" do
    project = projects(:orpheus)
    project.assign_attributes(build_time: "weekends", pace_minutes: 180)

    assert_equal [ Date.new(2026, 10, 3), Date.new(2026, 10, 4), Date.new(2026, 10, 10), Date.new(2026, 10, 11) ], project.build_days
  end

  test "setting up takes Hackatime and its project and the Slack channel; a repo and your idea post can wait" do
    project = projects(:orpheus)
    assert_equal 0, project.required_steps_done
    assert project.step_locked?("hackatime_project")

    project.assign_attributes(tracker: "hackatime", hackatime_projects: [ "rhythm-game" ])
    assert project.tracking?
    assert_not project.step_locked?("hackatime_project")
    assert_not project.set_up?

    project.slack_joined = true
    assert project.set_up?
    assert_equal 2, project.optional_steps_left

    project.assign_attributes(repo_later: true, idea_skipped: true)
    assert_equal 0, project.optional_steps_left
    assert project.step_open?("repo"), "a repo put off till later can still be added"
    assert_not project.step_open?("idea")
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

  test "linking a Hackatime project takes one you have, and unlinking takes it back off" do
    project = projects(:orpheus)
    project.available_hackatime_projects = Hackatime.projects("U0ORPHEUS")
    project.link_hackatime_project = "rhythm-game"
    assert project.valid?
    assert_equal [ "rhythm-game" ], project.hackatime_projects

    project.link_hackatime_project = "not-mine"
    assert_not project.valid?
    assert_equal [ "Hackatime projects don't include not-mine on Hackatime" ], project.errors.full_messages

    project.unlink_hackatime_project = "not-mine"
    project.unlink_hackatime_project = "rhythm-game"
    assert_empty project.hackatime_projects

    project.tracker = "hackatime"
    project.hackatime_projects = [ "rhythm-game" ]
    assert project.step_done?("hackatime_project")
    assert project.step_open?("hackatime_project")
  end

  test "only takes the answers onboarding offers" do
    project = projects(:orpheus)
    project.assign_attributes(tool: "notepad", prize: "switch", pace_minutes: 5, build_time: "never", tracker: "stopwatch",
                              repo_url: "my repo")

    assert_not project.valid?
    assert_equal %i[tool prize pace_minutes build_time tracker repo_url].sort, project.errors.attribute_names.sort
  end
end
