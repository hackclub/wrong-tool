# PSEUDO CODE (see Nudge).
#
# Nudges that always send when they apply, so the bandit never learns from them. The first one that applies wins:
# a program date, then a missing setup step, then saving a streak.
#
# Milestones don't go through here. They send from the Hackatime poll that notices them (outside quiet hours), so
# "first session logged!!" lands right after the session.
module Nudge::Fixed
  # wrong tool's own dates.
  PROGRAM = {
    "kickoff" => Program::DATES.begin,
    "three_days_left" => Program::DATES.end - 3,
    "last_day" => Program::DATES.end
  }.freeze

  # Sent at the slot, so streak savers come with the day's nudge rather than at 11pm.
  def self.for(context)
    program_nudge(context) || setup_nudge(context) || streak_saver(context)
  end

  def self.program_nudge(context)
    key = PROGRAM.key(context.today) or return
    key = "#{key}_done" if key != "kickoff" && context.hours >= Program::HOURS_PER_REWARD
    build(context, kind: "program", arm: key)
  end

  # One step at a time, in the order the project page lists them.
  def self.setup_nudge(context)
    project = context.project
    step =
      if project.tracker.blank? then "hackatime"
      elsif project.repo_url.blank? then "repo"
      end
    build(context, kind: "setup", arm: step) if step
  end

  def self.streak_saver(context)
    return unless context.streak >= 2 && context.minutes_today < Nudge::REWARD_MINUTES
    return if context.user.nudges.where(kind: "streak_saver", sent_at: context.now - context.streak.days..).exists?
    build(context, kind: "streak_saver", arm: "streak_saver")
  end

  # Milestones, from the Hackatime poll: "first_session", "halfway", "done". Each sends once. (Streak rewards tell you
  # themselves: see RewardNotifier.)
  def self.milestone(context, key)
    return if context.quiet? || context.user.nudges.where(kind: "milestone", arm: key).exists?
    build(context, kind: "milestone", arm: key)
  end

  def self.build(context, kind:, arm:)
    context.user.nudges.new(kind:, arm:, channel: context.channel, propensity: 1.0)
  end
end
