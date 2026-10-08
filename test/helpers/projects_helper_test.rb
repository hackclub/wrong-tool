require "test_helper"

class ProjectsHelperTest < ActionView::TestCase
  include PagesHelper

  test "how to get hours onto Hackatime depends on the tool" do
    lapse = projects(:orpheus)
    ssh = Project.new(tool: "ssh", tool_name: "SSH")
    code = Project.new(tool: "other", tool_name: "CMake")

    assert_match(/Record your sessions with Lapse. Any code you write in an editor counts through the Hackatime plugin/, project_hackatime_how(lapse))
    assert_match(/on the machine you SSH into/, project_hackatime_how(ssh))
    assert_match(/plugin in your editor/, project_hackatime_how(code))

    assert_match(/Record a session of building with Lapse, or write some code with the Hackatime plugin on/, project_first_time_how(lapse))
    assert_match(/over SSH with the plugin on/, project_first_time_how(ssh))
    assert_match(/Record a minute with Lapse/, project_hackatime_refresh_hint(lapse))
  end

  test "while there's nothing on Hackatime to pick, the project step and Clippy say to record with Lapse, or to log code" do
    project = projects(:orpheus)
    link_hackatime(project.user)
    project.available_hackatime_projects = []

    step = project_steps(project).find { |item| item[:key] == "hackatime_project" }
    assert_equal [ "Record your first session with Lapse", "it links itself" ], [ step[:title], step[:note] ]
    assert_equal "Hackatime's linked. Record with Lapse and your project links itself.", project_clippy_says(project)

    project.tool = "ssh"
    step = project_steps(project).find { |item| item[:key] == "hackatime_project" }
    assert_equal "Log your first time on Hackatime", step[:title]
    assert_equal "Hackatime's linked. Start building and your project links itself once you log time.", project_clippy_says(project)
  end

  test "the schedule fills in the days gone by how they went, then today, the goal day and the party" do
    project = projects(:orpheus)
    user = project.user
    user.streak_activities.create!(activity_date: Date.new(2026, 10, 6), coded_seconds: 45 * 60)
    user.streak_activities.create!(activity_date: Date.new(2026, 10, 7), coded_seconds: 20 * 60)
    user.streak_activities.create!(activity_date: Date.new(2026, 10, 9), coded_seconds: 90 * 60)
    user.update_columns(streak_skip_used_on: Date.new(2026, 10, 8))

    days = project_schedule(project, today: Date.new(2026, 10, 10))
    assert_equal [ "hit", "some", "skip", "hit", "today", nil ], days.first(6).map { _1[:state] }
    assert_equal [ "45m", "20m", "Skip", "1.5h", "Today", nil ], days.first(6).map { _1[:value] }
    assert_equal [ "Oct 6", "7", "8", "9", "10", "11" ], days.first(6).map { _1[:date] }
    assert_equal({ state: "goal", value: "Goal" }, days[13].slice(:state, :value))
    assert_equal({ date: "20", state: "due", value: "Due" }, days.last, "the deadline's the day after the goal, so no gap")
    assert_equal 15, days.size

    user.streak_activities.create!(activity_date: Date.new(2026, 10, 10), coded_seconds: 50 * 60)
    today = project_schedule(project, today: Date.new(2026, 10, 10))[4]
    assert_equal({ date: "10", state: "today", value: "50m", built: "hit" }, today, "today shows its time, and fills in")

    project.update!(pace_minutes: 60)
    days = project_schedule(project, today: Date.new(2026, 10, 10))
    assert_equal [ "goal", nil, "due" ], days.last(3).map { _1[:state] }
    assert days[-2][:gap], "days skipped between the goal and the deadline"
    assert_equal 12, days.size, "10 sessions, the gap and the deadline"

    project.update!(pace_minutes: 20)
    days = project_schedule(project, today: Date.new(2026, 10, 10))
    assert_equal "due", days.find { _1[:date] == "20" }[:state], "the deadline sits among your days when they run past it"
    assert_equal "goal", days.last[:state]

    project.update!(pace_minutes: 45)
    days = project_schedule(project, today: Date.new(2026, 10, 12))
    assert_equal [ "hit", "some", "skip", "hit", "hit", "missed", "today" ], days.first(7).map { _1[:state] }
    assert_equal "0", days[5][:value]
    assert_equal "party", project_schedule(project, today: Date.new(2026, 10, 6))[2][:state]
  end

  test "the schedule says when your hours would be in, and that you ship any time up to the deadline" do
    project = projects(:orpheus)
    assert_equal "14 sessions of 45 min gets you there by Oct 19. Ship any time up to Oct 20.", project_schedule_note(project)
    assert_equal({ label: "Done by", value: "Oct 19", note: "at this pace" }, project_goal(project).last)
  end
end
