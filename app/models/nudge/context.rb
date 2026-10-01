# PSEUDO CODE (see Nudge).
#
# Everything a nudge needs to know about someone right now: where they are in their local day, which bucket they're
# in, and the values Clippy's copy fills in.
class Nudge::Context
  # Building nothing for this long makes you lapsed.
  LAPSED_AFTER = 48.hours
  # Social copy needs enough people for the number to mean something.
  MIN_PEERS = 3

  attr_reader :user, :project, :now, :local_now

  def initialize(user, now)
    @user = user
    @project = user.project
    @now = now
    @local_now = now.in_time_zone(user.timezone)
  end

  def today
    local_now.to_date
  end

  def channel
    user.slack_id.present? && user.slack_dm_failed_at.nil? && user.slack_muted_at.nil? ? "slack" : "email"
  end

  # Within the 15 minutes after their slot, on a day they build.
  def in_slot?
    return false if project.build_time == "weekends" && !today.on_weekend?
    hour, min = Nudge::SLOTS.fetch(project.build_time).split(":").map(&:to_i)
    slot = local_now.change(hour:, min:)
    local_now.between?(slot, slot + 15.minutes)
  end

  def quiet?
    local_now.hour >= Nudge::QUIET_FROM || local_now.hour < Nudge::QUIET_UNTIL
  end

  # Not quiet hours, not opted out of their channel, under the caps, and they haven't built today already.
  def may_nudge?
    return false if quiet? || opted_out?
    return false if sent_today.exists? || user.nudges.where(sent_at: 7.days.ago..).count >= Nudge::WEEKLY_CAP
    minutes_today < Nudge::REWARD_MINUTES
  end

  def opted_out?
    channel == "email" && user.email_unsubscribed_at.present?
  end

  def sent_today
    user.nudges.where(sent_at: local_now.beginning_of_day..)
  end

  def dramatic_left?
    user.nudges.where(arm: "dramatic").count < Nudge::DRAMATIC_CAP
  end

  # Only bandit nudges use buckets. Not set up yet gets setup nudges instead.
  def bucket
    state =
      if hours.zero? then "zero_hours"
      elsif last_built_at < now - LAPSED_AFTER then "lapsed"
      elsif on_pace? then "on_pace"
      else "behind"
      end
    "#{state}/#{channel}"
  end

  # Have you built at least pace_minutes for every build day before today?
  def on_pace?
    hours >= project.build_days.count { |day| day < today } * project.pace_minutes / 60.0
  end

  # Hackatime, cached for the run.
  def hours = @hours ||= Hackatime.minutes_for(user, Program::DATES).fdiv(60).round(1)
  def minutes_today = @minutes_today ||= Hackatime.minutes_for(user, local_now.beginning_of_day..now)
  def last_built_at = @last_built_at ||= Hackatime.last_heartbeat_at(user)
  def streak = @streak ||= Hackatime.streak_for(user, minutes: Nudge::REWARD_MINUTES, timezone: user.timezone)

  # People on the same tool who built today.
  def peers
    @peers ||= Hackatime.users_built_on(today, Project.where(tool: project.tool).where.not(user:)).count
  end

  # What copy can fill in. Anything missing or not worth saying (a 0 streak, 1 peer) is left out, and copy that
  # needs it won't be picked.
  def vars
    @vars ||= build_vars
  end

  private
    def build_vars
      hours_left = [ Program::HOURS_PER_REWARD - hours, 0 ].max
      upcoming = helpers.project_rewards(project, streak:).find { |reward| reward[:next] }
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
        next_reward: upcoming&.dig(:label)&.downcase,
        days_to_reward: (upcoming[:day] - streak if upcoming),
        peers: (peers if peers >= MIN_PEERS),
        days_idle: (((now - last_built_at) / 1.day).floor if last_built_at && now - last_built_at >= LAPSED_AFTER)
      }.compact
    end

    def helpers
      ApplicationController.helpers
    end
end
