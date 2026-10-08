# Everything a nudge needs to know about someone right now: where they are in their local day, which bucket they're
# in, and the values Clippy's copy fills in. Hours, streaks and who else built come from their synced streak days
# (StreakActivity), brought up to date from Hackatime by refresh!. For a cheer, built_on is the streak day it's for.
class Nudge::Context
  # No streak day with any building in this many days makes you lapsed.
  LAPSED_AFTER_DAYS = 2
  # Social copy needs enough people for the number to mean something.
  MIN_PEERS = 3
  # A setup nudge for the same step waits this long before saying it again.
  SETUP_EVERY = 3.days
  # Overtake copy only when the one above you is within a session's reach.
  GAP_MINUTES = 60

  attr_reader :user, :project, :now, :local_now, :built_on

  def initialize(user, now = Time.current, built_on: nil)
    @user = user
    @project = user.project
    @now = now
    @local_now = now.in_time_zone(user.timezone.presence || "UTC")
    @built_on = built_on
  end

  def today
    local_now.to_date
  end

  # Their streak days, from Hackatime, as of now. If Hackatime can't be reached, what we last saw will do.
  def refresh!
    StreakActivity.sync_for_user!(user)
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    nil
  ensure
    user.reload
  end

  # Within the 15 minutes after their slot, on a day they build.
  def in_slot?
    return false if project.build_time == "weekends" && !today.on_weekend?
    hour, min = Nudge::SLOTS.fetch(project.build_time).split(":").map(&:to_i)
    slot = local_now.change(hour:, min:)
    local_now >= slot && local_now < slot + 15.minutes
  end

  def quiet?
    local_now.hour >= Nudge::QUIET_FROM || local_now.hour < Nudge::QUIET_UNTIL
  end

  # The next morning Clippy may speak: today's, or tomorrow's once it's late.
  def quiet_ends_at
    morning = local_now.change(hour: Nudge::QUIET_UNTIL, min: 0)
    local_now < morning ? morning : morning + 1.day
  end

  # Clippy can reach them: on Slack, not stopped, and the DM has worked before.
  def reachable?
    user.slack_id.present? && user.slack_muted_at.nil? && user.slack_dm_failed_at.nil?
  end

  # During wrong tool, not quiet hours, Clippy not stopped, under the caps, and they haven't built today already.
  # Cheers aren't counted against the caps: they're earned, and they only go once the day's building is done.
  def may_nudge?
    return false unless Program::DATES.cover?(today) && reachable?
    return false if quiet? || sent_today.exists?
    return false if user.nudges.delivered.where.not(kind: "cheer").where(sent_at: now - 7.days..).count >= Nudge::WEEKLY_CAP
    minutes_today < Nudge::REWARD_MINUTES
  end

  # A cheer for built_on: during wrong tool, not quiet hours, Clippy not stopped, the day's still today or
  # yesterday with its 20 minutes still there, and no cheer for that day, or any today, yet.
  def may_cheer?
    return false unless built_on && Program::DATES.cover?(today) && reachable?
    return false if quiet? || !(today - 1..today).cover?(built_on) || minutes_on(built_on) < Nudge::REWARD_MINUTES
    cheers = user.nudges.delivered.cheers
    !cheers.where(built_on:).or(cheers.where(sent_at: local_now.beginning_of_day..)).exists?
  end

  def sent_today
    user.nudges.delivered.where(sent_at: local_now.beginning_of_day..)
  end

  def dramatic_left?
    user.nudges.delivered.where(arm: "dramatic").count < Nudge::DRAMATIC_CAP
  end

  # Only bandit nudges use buckets.
  def bucket
    if hours.zero? then "zero_hours"
    elsif lapsed? then "lapsed"
    elsif on_pace? then "on_pace"
    else "behind"
    end
  end

  def lapsed?
    last_built_on.nil? || last_built_on < today - LAPSED_AFTER_DAYS
  end

  # Have you built at least pace_minutes for every build day before today?
  def on_pace?
    hours >= project.build_days.count { |day| day < today } * project.pace_minutes / 60.0
  end

  def hours = @hours ||= project.hours_logged
  def streak = user.current_streak
  def minutes_today = minutes_on(user.streak_today_date)
  def minutes_on(date) = user.streak_activities.find_by(activity_date: date)&.coded_seconds.to_i / 60
  def last_built_on = @last_built_on ||= user.streak_activities.where(coded_seconds: 1..).maximum(:activity_date)

  # People on the same tool who built today (or on the day a cheer's for).
  def peers
    @peers ||= StreakActivity.where(activity_date: built_on || user.streak_today_date, coded_seconds: 1..).where.not(user_id: user.id)
                             .joins(user: :project).where(projects: { tool: project.tool }).count
  end

  # What copy can fill in. Anything missing or not worth saying (a 0 streak, 1 peer) is left out, and copy that
  # needs it won't be picked.
  def vars
    @vars ||= build_vars
  end

  private
    def build_vars
      hours_left = [ Program::HOURS_PER_REWARD - hours, 0 ].max
      upcoming = helpers.project_rewards(project).find { |reward| reward[:state] == "next" }
      {
        first_name: user.first_name,
        title: project.title.downcase_first,
        tool_name: project.tool_name,
        prize: ProjectsHelper::PRIZE_SHORT_NAMES.fetch(project.prize),
        hours: hours,
        hours_left: hours_left.round(1),
        percent: (hours * 100 / Program::HOURS_PER_REWARD).round,
        sessions_left: (hours_left * 60 / project.pace_minutes).ceil,
        session_percent: (project.pace_minutes * 100.0 / (Program::HOURS_PER_REWARD * 60)).round,
        pace: project.pace_minutes,
        build_time: project.build_time,
        finish_on: project.finish_on.strftime("%b %-d"),
        local_time: local_now.strftime("%-l%P").strip,
        days_left: (Program::DATES.end - today).to_i,
        streak: (streak if streak.positive?),
        streak_next: (streak + 1 if streak.positive?),
        next_reward: (upcoming[:label].downcase if upcoming && streak.positive?),
        days_to_reward: (upcoming[:days] - streak if upcoming && streak.positive?),
        peers: (peers if peers >= MIN_PEERS),
        days_idle: ((today - last_built_on).to_i if last_built_on && lapsed?),
        **leaderboard_vars,
        **cheer_vars
      }.compact
    end

    # Where you are on this week's board, for the overtake copy: your rank, who's just above you and how many
    # minutes would pass them, when that's one session's worth (GAP_MINUTES). Only once you have hours this week:
    # at zero everyone's tied, and a rank among ties means nothing. passed_by is who went past you since
    # yesterday's snapshot, if you've dropped and they're now the one above.
    def leaderboard_vars
      return {} unless project.set_up? && project.hours_this_week.positive?
      place = Leaderboard.place_of(project) or return {}
      gap = place.gap_minutes
      close = gap && gap.positive? && gap <= GAP_MINUTES
      dropped = place.change&.negative?
      { rank: place.rank, above: (place.above.user.public_name if close), gap_minutes: (gap if close),
        passed_by: (place.above.user.public_name if close && dropped), places_lost: (-place.change if dropped) }
    end

    # For a cheer: how long they built on the day it's for, and which day that is from where they are now ("today"
    # or "yesterday", so a cheer held for the morning still reads right).
    def cheer_vars
      return {} unless built_on
      { minutes: minutes_on(built_on), day: built_on == today ? "today" : "yesterday", next_day: built_on == today ? "tomorrow" : "today" }
    end

    def helpers
      ApplicationController.helpers
    end
end
