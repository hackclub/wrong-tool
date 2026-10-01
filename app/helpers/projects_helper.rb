module ProjectsHelper
  PRIZE_NAMES = { "rg35xx" => "ANBERNIC RG35XX Pro", "miyoo" => "Miyoo Mini Plus" }.freeze
  PRIZE_SHORT_NAMES = { "rg35xx" => "RG35XX", "miyoo" => "Miyoo" }.freeze
  PACE_LABELS = { 20 => "20 min", 45 => "45 min", 60 => "1 hr", 120 => "2 hrs", 180 => "3 hrs" }.freeze
  BUILD_TIME_LABELS = { "after school" => "after school", "evening" => "evenings", "late night" => "late nights",
                        "weekends" => "weekends" }.freeze
  # When today's session is, by when you build.
  BUILD_TIME_SOON = { "after school" => "after school", "evening" => "this evening", "late night" => "tonight",
                      "weekends" => "today" }.freeze

  def wrong_tool_slack_url
    "https://hackclub.slack.com/app_redirect?channel=wrong-tool"
  end

  def project_prize_name(project)
    PRIZE_NAMES.fetch(project.prize)
  end

  # "Oct 15"
  def project_date(date)
    date.strftime("%b %-d")
  end

  def project_pace_label(minutes)
    PACE_LABELS.fetch(minutes)
  end

  # "rhythm_game_in_spreadsheet"
  def project_file_name(project)
    project.title.downcase.delete_prefix("a ").delete_prefix("an ").gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")[0, 36]
  end

  # "10 hrs · 45 min a day · done by Oct 15 · Miyoo Mini Plus"
  def project_meta(project)
    per = project.build_time == "weekends" ? "a session" : "a day"
    [ "#{hours_per_reward} hrs", "#{project_pace_label(project.pace_minutes)} #{per}",
      "done by #{project_date(project.finish_on)}", project_prize_name(project) ].join(" · ")
  end

  # Your hours always come from Hackatime; if you're writing code (or might be), that's its editor extension.
  def project_hackatime_how(project)
    if project.code_tool? then "Install the Hackatime extension in your editor."
    elsif project.tool == "other" then "Use the editor extension, or record with Lapse. Lapse syncs to Hackatime."
    end
  end

  # Your Hackatime projects you haven't linked yet, for the dropdown, or why there aren't any to show.
  def project_hackatime_choices(project, refresh: false)
    projects = Hackatime.projects(project.user.slack_id, refresh:)
    { projects: projects.reject { |hackatime| project.hackatime_projects.include?(hackatime.name) } }
  rescue Hackatime::NotFound
    { projects: [], problem: "Hackatime doesn't know you yet. Sign in to Hackatime with your Hack Club Slack, then refresh." }
  rescue Hackatime::Unavailable
    { projects: [], problem: "Couldn't reach Hackatime just now. Try refreshing." }
  end

  # "harbor · 214.7 hrs"
  def project_hackatime_option(hackatime)
    "#{hackatime.name} · #{hackatime.hours.to_s.delete_suffix(".0")} hrs"
  end

  # The setup steps as the page shows them. The one you're on (the step you picked, if you can still do it, or the
  # first one left) opens to show how to do it.
  def project_steps(project, step: nil)
    current = project.step_open?(step.to_s) ? step.to_s : Project::SETUP_STEPS.find { |key| !project.step_done?(key) && !project.step_locked?(key) }
    Project::SETUP_STEPS.map do |key|
      # A step you reopen (the repo you'd put off) reads as still to do.
      done = project.step_done?(key) && key != current
      title, note = project_step_label(project, key, done)
      { key:, number: Project::SETUP_STEPS.index(key) + 1, title:, note:, done:, locked: project.step_locked?(key),
        current: key == current, openable: key != current && project.step_open?(key) }
    end
  end

  # What Clippy says while you set up, and after.
  def project_clippy_says(project)
    if !project.tracker then "Nothing's linked yet, so your hours won't count."
    elsif project.hackatime_projects.none? then "Hackatime's linked. Which project is yours?"
    elsif !project.slack_joined? then "Hours count now. Join #wrong-tool and you're set."
    else "All set. 20 min today starts your streak."
    end
  end

  # =SETUP(hackatime, project, slack) → #REF! until hours count and you're in the channel.
  def project_formula(project)
    ready = project.tracking? && project.slack_joined?
    "=SETUP(hackatime, project, slack)  →  #{ready ? "TRUE" : "#REF!"}"
  end

  # "I'm building a rhythm game in Spreadsheet. 10 hrs, shipping Oct 15."
  def project_idea_post(project)
    "I'm building #{project.title.sub(/\A\w/, &:downcase)}. #{hours_per_reward} hrs, shipping #{project_date(project.finish_on)}."
  end

  # Hours logged, your daily pace (which you can change) and when you ship.
  def project_goal(project)
    [
      { label: "Logged", value: "#{project.hours_logged} of #{hours_per_reward} hrs", note: "for the #{project_prize_name(project)}" },
      { label: "Daily pace", value: project_pace_label(project.pace_minutes), note: BUILD_TIME_LABELS.fetch(project.build_time),
        pace: true },
      { label: "Ship by", value: project_date(project.finish_on), note: "if you keep pace" }
    ]
  end

  # The milestones along your hours track (which runs to the last one), and whether you've reached each.
  def project_milestones(project)
    most = Program::MILESTONES.keys.max
    Program::MILESTONES.map do |hours, reward|
      reached = project.hours_logged >= hours
      { hours:, label: "#{hours} hrs · #{reached && reward == "shoutout" ? "posted" : reward}", reached:,
        at: hours * 100.0 / most, last: hours == most }
    end
  end

  def project_hours_percent(project)
    [ project.hours_logged * 100.0 / Program::MILESTONES.keys.max, 100 ].min
  end

  # Your build days, with today, the play party and ship day marked.
  def project_schedule(project, today: Date.current)
    days = project.build_days
    days.map.with_index do |day, index|
      label = index.zero? || day.day == 1 ? project_date(day) : day.day.to_s
      state = if day == today then "today"
      elsif index == days.size - 1 then "ship"
      elsif day == Program::PLAY_PARTY_ON then "party"
      end
      { date: label, state:, value: { "today" => "Today", "ship" => "Ship", "party" => "Party" }[state] }
    end
  end

  # A calendar-page date for the Events card: "OCT" over "8".
  def project_event_date(date)
    safe_join([ tag.span(date.strftime("%b"), class: "project__event-month"), tag.span(date.day, class: "project__event-day") ])
  end

  # "Today: 45 min, this evening"
  def project_today(project)
    "Today: #{project_pace_label(project.pace_minutes)}, #{BUILD_TIME_SOON.fetch(project.build_time)}"
  end

  # The week ahead on your streak card, starting today.
  def project_streak_week(today: Date.current)
    (today...today + 7).map { |day| { letter: day.strftime("%a")[0], today: day == today } }
  end

  # Streak rewards: a gold star on day 3, a skip day on day 7, and stickers on your last build day (only the
  # ones your plan reaches). The first one you haven't got yet is next.
  def project_rewards(project)
    streak = project.streak
    days = project.build_days.size
    rewards = [
      { day: 3, label: "Gold star for Clippy" },
      { day: 7, label: "+1 skip day" },
      { day: days, label: "Sticker pack with your #{PRIZE_SHORT_NAMES.fetch(project.prize)}" }
    ].select { |reward| reward[:day] <= days }.uniq { |reward| reward[:day] }
    upcoming = rewards.find { |reward| reward[:day] > streak }
    rewards.map do |reward|
      earned = streak >= reward[:day]
      left = reward[:day] - streak
      state = if earned then "earned" elsif reward.equal?(upcoming) then "next" else "later" end
      reward.merge(state:, status: earned ? "Earned" : pluralize(left, "day"))
    end
  end

  # Everyone set up, ranked by hours this week or streak, and you (last, with dashes, until you're set up).
  def leaderboard(you, sort: "week")
    key = sort == "streak" ? :streak : :hours_this_week
    others = Project.includes(:user, screenshot_attachment: :blob).where.not(id: you.id).select(&:set_up?)
    ranked = (others + [ you ]).sort_by { |project| [ project.set_up? ? 0 : 1, -project.public_send(key), project.user.name.to_s ] }
    ranked.map.with_index(1) do |project, rank|
      mine = project == you
      { rank:, you: mine, name: mine ? "You" : project.user.first_name.presence || project.user.name,
        initial: leaderboard_initial(project.user), building: project.title, off: !project.set_up?,
        screenshot: (project.screenshot if project.screenshot.attached? && project.screenshot.blob.persisted?),
        hours: project.hours_this_week, streak: project.streak }
    end
  end

  # The top three this week as stairs (second, first, third), with you on a step of your own if you're further down,
  # and how far it is to pass whoever's just above you.
  def leaderboard_stairs(you)
    rows = leaderboard(you).reject { |row| row[:off] && !row[:you] }
    mine = rows.find { |row| row[:you] }
    places = rows.first(3).values_at(1, 0, 2).compact.map { |row| row.merge(place: row[:rank].to_s, label: row[:rank].to_s) }
    places << mine.merge(place: "you", label: "##{mine[:rank]}") if mine[:rank] > 3
    above = rows[rows.index(mine) - 1] if mine[:rank] > 1
    note = above ? "Hours this week · #{above[:hours] - mine[:hours]} hrs to pass #{above[:name]}" : "Hours this week. You're on top."
    [ places, note ]
  end

  # Every wrong tool, the games shipped in it, and who's building one. The tools onboarding offers are always here
  # (even with nothing in them yet), with any others people are building in.
  def hall_of_wrong(you: nil)
    projects = Project.includes(:user, :ships).to_a
    names = %w[Spreadsheet Figma Email SSH Shaders] | projects.map(&:tool_name)
    names.map do |name|
      in_tool = projects.select { |project| project.tool_name.casecmp?(name) }
      shipped = in_tool.select(&:shipped?)
      building = in_tool.size - shipped.size
      games = if shipped.any?
        shipped.map { |project| "#{project.title} by #{project.user.first_name.presence || project.user.name}" }.to_sentence
      else
        "Nobody yet.#{" #{pluralize(building, "person")} building one." if building.positive?}"
      end
      { tool: name, shipped: shipped.size, games:, mine: you&.tool_name&.casecmp?(name) }
    end.sort_by.with_index { |row, index| [ -row[:shipped], index ] }
  end

  # "2 games shipped in Spreadsheet, 1 in Figma." and where nothing's been shipped yet.
  def hall_of_wrong_summary(rows)
    shipped, empty = rows.partition { |row| row[:shipped].positive? }
    counts = shipped.map.with_index { |row, index| "#{index.zero? ? pluralize(row[:shipped], "game") + " shipped" : row[:shipped]} in #{row[:tool]}" }
    [ (counts.join(", ") + "." if counts.any?), ("Nothing yet in #{empty.map { |row| row[:tool] }.to_sentence(last_word_connector: " or ", two_words_connector: " or ")}." if empty.any?) ]
  end

  def leaderboard_initial(user)
    (user.first_name.presence || user.name.to_s)[0]&.upcase
  end

  private
    def project_step_label(project, key, done)
      case key
      when "hackatime" then done ? [ "Hackatime linked" ] : [ "Link Hackatime" ]
      when "hackatime_project"
        if project.hackatime_projects.any? && done then [ "Linked to #{project.hackatime_projects.to_sentence}" ]
        elsif project.hackatime_projects.any? then [ "Change your Hackatime projects" ]
        else [ "Link your Hackatime project", "after Hackatime" ]
        end
      when "slack" then done ? [ "Joined #wrong-tool" ] : [ "Join #wrong-tool on Slack" ]
      when "repo"
        if project.repo_url.present? then [ "Repo added" ]
        elsif done then [ "Git repo", "add before you ship" ]
        else [ "Add your git repo", "before you ship" ]
        end
      when "idea"
        if project.idea_posted? then [ "Idea posted" ]
        elsif done then [ "Idea post skipped" ]
        else [ "Post your idea in #wrong-tool", "optional" ]
        end
      end
    end
end
