require "test_helper"

class ProjectsHelperTest < ActionView::TestCase
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
end
