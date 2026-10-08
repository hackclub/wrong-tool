module ProjectsHelper
  PRIZE_NAMES = { "rg35xx" => "ANBERNIC RG35XX Pro", "miyoo" => "Miyoo Mini Plus" }.freeze
  PRIZE_SHORT_NAMES = { "rg35xx" => "RG35XX", "miyoo" => "Miyoo" }.freeze
  PACE_LABELS = { 20 => "20 min", 45 => "45 min", 60 => "1 hr", 120 => "2 hrs", 180 => "3 hrs" }.freeze
  BUILD_TIME_LABELS = { "after school" => "after school", "evening" => "evenings", "late night" => "late nights",
                        "weekends" => "weekends" }.freeze
  # When today's session is, by when you build.
  BUILD_TIME_SOON = { "after school" => "after school", "evening" => "this evening", "late night" => "tonight",
                      "weekends" => "today" }.freeze

  def project_prize_name(project)
    PRIZE_NAMES.fetch(project.prize)
  end

  # "1.5 of 10 hrs"
  def project_hours_label(project, hours = project.hours_logged)
    "#{project_hours(hours)} of #{hours_per_reward} hrs"
  end

  # 1.5, or 2 rather than 2.0
  def project_hours(hours)
    hours.to_s.delete_suffix(".0")
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

  # Your hours always come through Hackatime: from its editor plugin if you're writing code (over SSH, that's on the
  # machine you SSH into), or from Lapse recordings, which sync to it.
  def project_hackatime_how(project)
    if project.tool == "ssh" then "Install the Hackatime plugin in the editor on the machine you SSH into, not just your laptop. That's where your hours come from."
    elsif project.code_tool? then "Install the Hackatime plugin in your editor. That's where your hours come from."
    else "Record your sessions with Lapse. Any code you write in an editor counts through the Hackatime plugin instead. Both land on Hackatime, so linking is how your hours reach us."
    end
  end

  # How to get your first time onto Hackatime, by tool, while there's nothing there to pick.
  def project_first_time_how(project)
    if project.tool == "ssh" then "Write a line of code over SSH with the plugin on. It shows up here and links itself."
    elsif project.code_tool? then "Write a line of code with the plugin on. It shows up here and links itself."
    else "Record a session of building with Lapse, or write some code with the Hackatime plugin on. Either lands on Hackatime as a project and links itself."
    end
  end

  # "Don't see it?" for the Hackatime projects dropdown, by tool.
  def project_hackatime_refresh_hint(project)
    if project.tool == "ssh" then "Don't see it? Write a line of code over SSH with the plugin on, then refresh."
    elsif project.code_tool? then "Don't see it? Write a line of code with the plugin on, then refresh."
    else "Don't see it? Record a minute with Lapse, or write a line of code with the plugin on, then refresh."
    end
  end

  # Your Hackatime projects for the dropdown, the linked ones ticked (including any Hackatime no longer lists, so
  # they can be unticked), or why there aren't any to show.
  def project_hackatime_choices(project, refresh: false)
    projects = Hackatime.projects(project.user, refresh:)
    missing = project.hackatime_projects - projects.map(&:name)
    choices = missing.map { |name| { name:, note: "not on Hackatime now", linked: true } } +
      projects.map { |hackatime| { name: hackatime.name, note: "#{hackatime.hours.to_s.delete_suffix(".0")} hrs", linked: project.hackatime_projects.include?(hackatime.name) } }
    { projects: choices }
  rescue Hackatime::NotLinked, Hackatime::Expired
    { projects: [], problem: "Your Hackatime link expired.", relink: true }
  rescue Hackatime::Unavailable
    { projects: [], problem: "Couldn't reach Hackatime just now. Try refreshing." }
  end

  # "Link project", "Link 2 projects", or "Pick a project" with none ticked.
  def project_hackatime_link_label(count)
    count.zero? ? "Pick a project" : "Link #{count == 1 ? "project" : "#{count} projects"}"
  end

  # The setup steps as the page shows them. The one you're on (the step you picked, if you can still do it, or the
  # first one left) opens to show how to do it. Picking your Hackatime project waits its turn while there's nothing on
  # Hackatime to pick (it links itself once there is), but stays open too, so how to get that first time there (record
  # with Lapse, or log some code) is in view.
  def project_steps(project, step: nil)
    current = project.step_open?(step.to_s) ? step.to_s : Project::SETUP_STEPS.find { |key| !project.step_settled?(key) && !project.step_locked?(key) }
    Project::SETUP_STEPS.map do |key|
      # A step you reopen (the repo you'd put off) reads as still to do.
      done = project.step_done?(key) && key != current
      title, note = project_step_label(project, key, done)
      waiting = key == "hackatime_project" && project.waiting_for_hackatime_project? && project.hackatime_projects.none?
      { key:, number: Project::SETUP_STEPS.index(key) + 1, title:, note:, done:, locked: project.step_locked?(key),
        current: key == current, openable: key != current && project.step_open?(key), waiting: }
    end
  end

  # What Clippy says while you set up, and after.
  def project_clippy_says(project)
    if !project.hackatime_linked? then "Nothing's linked yet, so your hours won't count."
    elsif project.hackatime_projects.none? && !project.waiting_for_hackatime_project? then "Hackatime's linked. Which project is yours?"
    elsif !project.setup_finished?
      project.tracking? ? "Hours count now. A couple of quick things and you're in." : "Hackatime's linked. #{project_links_itself(project)}"
    elsif project.waiting_for_hackatime_project? then "All set. #{project_links_itself(project)}"
    elsif project.streak.positive? then "#{pluralize(project.streak, "day")} in a row. 20 min today keeps it going."
    else "All set. 20 min today starts your streak."
    end
  end

  # How Clippy feels about where you're at (a mood in mascot/clippy.js).
  def project_clippy_mood(project)
    if !project.hackatime_linked? then "attention"
    elsif project.hackatime_projects.none? && !project.waiting_for_hackatime_project? then "thinking"
    elsif !project.setup_finished? then "explaining"
    else "happy"
    end
  end

  # =SETUP(hackatime, project) → #REF! until Hackatime's linked, #N/A while your hours don't count yet (no Hackatime
  # project linked), then TRUE.
  def project_formula(project)
    result = if !project.set_up? then "#REF!" elsif !project.tracking? then "#N/A" else "TRUE" end
    "=SETUP(hackatime, project)  →  #{result}"
  end

  # Hours logged, your daily pace (which you can change) and when you'd be done at it. (Ship day's the program's
  # deadline, on the Events card: this is the day your hours would be in.)
  def project_goal(project)
    [
      { label: "Logged", value: project_hours_label(project), note: "for the #{project_prize_name(project)}" },
      { label: "Daily pace", value: project_pace_label(project.pace_minutes), note: BUILD_TIME_LABELS.fetch(project.build_time),
        pace: true },
      { label: "Done by", value: project_date(project.finish_on), note: "at this pace" }
    ]
  end

  # "14 sessions of 45 min gets you there by Oct 16. Ship any time up to Oct 20."
  def project_schedule_note(project)
    "#{pluralize(project.build_days.size, "session")} of #{project_pace_label(project.pace_minutes)} gets you there by " \
      "#{project_date(project.finish_on)}. Ship any time up to #{project_date(Program::DATES.end)}."
  end

  # The milestones along your hours track (which runs to the last one), and whether you've reached each. The
  # shoutout reads "posted" once it has been (Reward::HOURS), which follows the next sync after you reach it.
  def project_milestones(project)
    most = Program::MILESTONES.keys.max
    Program::MILESTONES.map do |hours, reward|
      reached = project.hours_logged >= hours
      posted = reward == "shoutout" && project.user.earned?("hours_shoutout")
      { hours:, label: "#{hours} hrs · #{posted ? "posted" : reward}", reached:, at: hours * 100.0 / most, last: hours == most }
    end
  end

  def project_hours_percent(project)
    [ project.hours_logged * 100.0 / Program::MILESTONES.keys.max, 100 ].min
  end

  # Your build days as cells. The days gone show how they went, from Hackatime: "hit" with your pace's minutes on
  # your linked projects (or more), "some" with less, "missed" with none, or "skip" for the one your skip day
  # covered. Then today, and ahead of it the play party and the day your hours would be in ("goal"). Days run on
  # streak time (2am to 2am where you are), like the streak does.
  def project_schedule(project, today: project.user.streak_today_date)
    days = project.build_days
    seconds = project.user.streak_activities.for_range(days.first...today).pluck(:activity_date, :coded_seconds).to_h
    skipped_on = project.user.streak_skip_used_on
    days.map.with_index do |day, index|
      label = index.zero? || day.day == 1 ? project_date(day) : day.day.to_s
      state, value =
        if day == today then [ "today", "Today" ]
        elsif day < today && day == skipped_on then [ "skip", "Skip" ]
        elsif day < today
          built = seconds.fetch(day, 0)
          if built.zero? then [ "missed", "0" ]
          else [ built >= project.pace_minutes * 60 ? "hit" : "some", project_day_time(built) ]
          end
        elsif index == days.size - 1 then [ "goal", "Goal" ]
        elsif day == Program::PLAY_PARTY_ON then [ "party", "Party" ]
        end
      { date: label, state:, value: }
    end
  end

  # A day's building, short enough for its cell: "45m" under an hour, "1.5h" from there.
  def project_day_time(seconds)
    minutes = seconds / 60
    minutes < 60 ? "#{minutes}m" : "#{project_hours((seconds / 360.0).round / 10.0)}h"
  end

  # A calendar-page date for the Events card: "OCT" over "8".
  def project_event_date(date)
    safe_join([ tag.span(date.strftime("%b"), class: "project__event-month"), tag.span(date.day, class: "project__event-day") ])
  end

  # "Today: 45 min, this evening"
  def project_today(project)
    "Today: #{project_pace_label(project.pace_minutes)}, #{BUILD_TIME_SOON.fetch(project.build_time)}"
  end

  # When your streak was last checked with Hackatime: "Checked just now", "Checked 5 minutes ago".
  def project_streak_checked(user)
    checked_at = user.streak_synced_at
    if checked_at.nil? then "Not checked yet"
    elsif checked_at > 1.minute.ago then "Checked just now"
    else "Checked #{time_ago_in_words(checked_at)} ago"
    end
  end

  # This week on your streak card, Sunday to Saturday, with the days you hit 20 minutes.
  def project_streak_week(project)
    project.user.streak_week
  end

  # Streak rewards (Reward::STREAK), earned or how many days off. The first one you haven't earned is next.
  def project_rewards(project)
    streak = project.streak
    rewards = Reward::STREAK.map { |reward| reward.merge(earned: project.user.earned?(reward[:key])) }
    upcoming = rewards.find { |reward| !reward[:earned] }
    rewards.map do |reward|
      state = if reward[:earned] then "earned" elsif reward.equal?(upcoming) then "next" else "later" end
      reward.merge(state:, status: reward[:earned] ? "Earned" : pluralize([ reward[:days] - streak, 1 ].max, "day"))
    end
  end

  # Everyone set up, ranked by hours this week or streak (Leaderboard), and you (last, with dashes, until you're set
  # up). A streak long enough for the flame reward shows one, a pair that's done a pomodoro together shows your
  # buddy, and the week board shows how far you've moved since yesterday's snapshot.
  def leaderboard(you, sort: "week")
    places = Leaderboard.places(sort:)
    places << Leaderboard::Place.new(project: you, rank: places.size + 1, above: nil) unless you.set_up?
    places.map do |place|
      project = place.project
      mine = project == you
      { rank: place.rank, you: mine, name: mine ? "You" : project.user.public_name,
        user: project.user, building: project.title, off: !project.set_up?,
        screenshot: (project.screenshot if project.screenshot.attached? && project.screenshot.blob.persisted?),
        hours: project.hours_this_week, streak: project.streak, change: (place.change if sort == "week" && project.set_up?),
        flame: project.streak >= Reward.definition("flame")[:days], buddy: leaderboard_buddy(project) }
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
    note = above ? "Hours this week · #{(above[:hours] - mine[:hours]).round(1)} hrs to pass #{above[:name]}" : "Hours this week. You're in first."
    [ places, note ]
  end

  # The sidebar's cards once you're set up, as the rows they fold into: your streak, your buddy, the play party and
  # where you are on the leaderboard. Your streak's open, unless your buddy needs you (a pomodoro to join).
  def project_side_sections(project)
    buddy = project.buddy
    live = project.pair&.live_pomodoro
    buddy_waiting = live.present? && !live.in?(project)
    rank = leaderboard(project).find { |row| row[:you] }[:rank]
    sections = {
      streak: { icon: "local-fire-department", label: "Day streak",
                value: project.streak.positive? ? pluralize(project.streak, "day") : "Not yet", tone: project.streak.positive? ? "good" : "quiet" },
      buddy: { icon: "group", label: buddy ? "You + #{buddy_name(buddy)}" : "Buddy",
               value: buddy ? pluralize(project.pair.pair_weeks, "pair week") : project.buddy_invited? ? "Pending" : "Invite",
               tone: buddy ? nil : project.buddy_invited? ? "pending" : "link", dot: buddy_waiting },
      events: { icon: "event", label: "Play party", value: project_date(Program::PLAY_PARTY_ON), tone: "party" },
      leaderboard: { icon: "leaderboard", label: "Leaderboard", value: "##{rank}" }
    }
    sections[buddy_waiting ? :buddy : :streak][:open] = true
    sections.to_h { |key, section| [ key, section.merge(key:) ] }
  end


  # "Record with Lapse and your project links itself.", or for code, once you log time.
  def project_links_itself(project)
    project.lapse_tool? ? "Record with Lapse and your project links itself." : "Start building and your project links itself once you log time."
  end

  private
    # Your buddy, once the two of you have done a pomodoro together.
    def leaderboard_buddy(project)
      pair = project.pair
      pair.buddy_of(project) if pair&.earned?("pair_listed")
    end

    def project_step_label(project, key, done)
      case key
      when "hackatime" then done ? [ "Hackatime linked" ] : [ "Link Hackatime" ]
      when "hackatime_project"
        if project.hackatime_projects.any? && done then [ "Linked to #{project.hackatime_projects.to_sentence}" ]
        elsif project.hackatime_projects.any? then [ "Change your Hackatime projects" ]
        elsif project.step_locked?(key) then [ "Link your Hackatime project", "after Hackatime" ]
        elsif project.waiting_for_hackatime_project? && project.lapse_tool? then [ "Record your first session with Lapse", "it links itself" ]
        elsif project.waiting_for_hackatime_project? then [ "Log your first time on Hackatime", "it links itself" ]
        else [ "Link your Hackatime project", "so your hours count" ]
        end
      when "repo"
        if project.repo_url.present? then [ "Repo added" ]
        elsif done then [ "Git repo", "add before you ship" ]
        else [ "Add your git repo", "before you ship" ]
        end
      when "buddy"
        if (buddy = project.buddy) then [ "Paired with #{buddy_name(buddy)}" ]
        elsif project.buddy_invited? then [ "Buddy invite sent", "you'll be paired when they sign up" ]
        elsif done then [ "Buddy skipped", "you can pair up any time" ]
        else [ "Bring a buddy", "optional" ]
        end
      end
    end
end
