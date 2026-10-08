# Nudges that always send when they apply, so the bandit never learns from them. The first one that applies wins:
# a program date, then a milestone, then a missing setup step, then saving a streak.
module Nudge::Fixed
  # wrong tool's own dates.
  PROGRAM = {
    "kickoff" => Program::DATES.begin,
    "three_days_left" => Program::DATES.end - 3,
    "last_day" => Program::DATES.end
  }.freeze

  # Hours on Hackatime that each milestone is for, in order. Each sends once, and reaching a later one first means
  # the earlier ones don't send at all.
  MILESTONES = { "first_session" => 0.1, "halfway" => Program::HOURS_PER_REWARD / 2.0, "done" => Program::HOURS_PER_REWARD }.freeze

  # Sent at their slot, so streak savers come with the day's nudge rather than at 11pm.
  def self.for(context)
    program_nudge(context) || milestone(context) || setup_nudge(context) || streak_saver(context)
  end

  def self.program_nudge(context)
    key = PROGRAM.key(context.today) or return
    key = "#{key}_done" if key != "kickoff" && context.hours >= Program::HOURS_PER_REWARD
    return if context.user.nudges.delivered.where(kind: "program", arm: key).exists?
    build(context, kind: "program", arm: key)
  end

  def self.milestone(context)
    key = MILESTONES.select { |_, hours| context.hours >= hours }.keys.last or return
    later = MILESTONES.keys.drop(MILESTONES.keys.index(key))
    return if context.user.nudges.delivered.where(kind: "milestone", arm: later).exists?
    build(context, kind: "milestone", arm: key)
  end

  # One step at a time, in the order the project page lists them, and not every day. After linking Hackatime comes
  # getting time onto it: with nothing there since wrong tool started, Clippy says how (Lapse, or the editor plugin
  # for code); with time there and no project picked, he asks you to pick one, unless there's one new project, which
  # is linked for you instead (Project#auto_link_hackatime_project, the same as opening your project page would).
  def self.setup_nudge(context)
    project = context.project
    step =
      if !project.hackatime_linked? then "hackatime"
      elsif (hackatime_step = hackatime_project_step(context)) then hackatime_step
      elsif project.repo_url.blank? && !project.repo_later? then "repo"
      end
    return unless step
    return if context.user.nudges.delivered.where(kind: "setup", arm: step, sent_at: context.now - Nudge::Context::SETUP_EVERY..).exists?
    build(context, kind: "setup", arm: step)
  end

  # Picking your Hackatime project, or getting time onto Hackatime first (lapse or plugin, by tool): whichever's
  # next, or nothing once a project's picked, one got linked for you just now, or Hackatime can't be reached today.
  def self.hackatime_project_step(context)
    project = context.project
    return if project.hackatime_projects.any?

    available = Hackatime.projects(context.user)
    return if project.auto_link_hackatime_project(available)
    return "hackatime_project" if available.any? { |each| each.seconds.positive? }
    project.lapse_tool? ? "lapse" : "plugin"
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  end

  def self.streak_saver(context)
    return unless context.streak >= 2 && context.minutes_today < Nudge::REWARD_MINUTES
    return if context.user.nudges.delivered.where(kind: "streak_saver", sent_at: context.now - context.streak.days..).exists?
    build(context, kind: "streak_saver", arm: "streak_saver")
  end

  def self.build(context, kind:, arm:)
    context.user.nudges.new(kind:, arm:, propensity: 1.0)
  end
end
