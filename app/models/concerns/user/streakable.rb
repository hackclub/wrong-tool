# Your streak: days in a row you built at least 20 minutes on your linked Hackatime projects, kept up to date from
# Hackatime in the background. Today doesn't break it until it's over, and once a streak reaches the skip day reward
# (Reward::STREAK), the first day you miss after that doesn't break it either. (From Stardance's streaks.)
module User::Streakable
  extend ActiveSupport::Concern

  # How long a sync holds off the next one, so every page load doesn't ask Hackatime.
  STREAK_SYNC_THROTTLE = 15.minutes

  # How long hitting Refresh holds off the next one, so mashing it doesn't hammer Hackatime.
  MANUAL_STREAK_SYNC_THROTTLE = 20.seconds

  included do
    has_many :streak_activities, dependent: :destroy
    has_many :rewards, dependent: :destroy
  end

  def streak_today_date
    StreakActivity.streak_date_for(Time.current, timezone)
  end

  # Your streak, and then whatever streak rewards it's reached (and your pair's, since your hours moved).
  def recalculate_streak!
    streak, skipped_on = calculate_current_streak
    update_columns(current_streak: streak, streak_skip_used_on: skipped_on)
    Reward.award_streak!(self)
    project&.pair&.then { |pair| Reward.award_pair!(pair) }
  end

  # Hours on your linked Hackatime projects over some days, as of the last sync. Weekly hours and pair weeks come from
  # here rather than asking Hackatime.
  def hours_in(dates)
    (streak_activities.for_range(dates).sum(:coded_seconds) / 3600.0).round(1)
  end

  def earned?(key) = rewards.any? { |reward| reward.key == key }

  # Queues a sync, unless one went out in the last STREAK_SYNC_THROTTLE.
  def sync_streak_if_stale!
    return unless project&.tracking?
    return if Rails.cache.read(streak_sync_throttle_key)

    sync_streak!
  end

  # Your linked Hackatime projects changed, so time that counted before might not now (or the other way round):
  # every day's rebuilt from the start, straight away. With none linked, there's no streak.
  def refresh_streak!
    if project&.tracking?
      update_column(:streak_synced_at, nil)
      sync_streak!
    else
      streak_activities.delete_all
      update_columns(current_streak: 0, streak_skip_used_on: nil, streak_synced_at: nil)
    end
  end

  def sync_streak!
    Rails.cache.write(streak_sync_throttle_key, true, expires_in: STREAK_SYNC_THROTTLE)
    StreakSyncJob.perform_later(id)
  end

  # Hitting Refresh wants numbers now, so this syncs inline rather than queueing, and holds off the background sync
  # too.
  def sync_streak_now!
    return unless project&.tracking?
    return if Rails.cache.read(manual_streak_sync_key)

    Rails.cache.write(manual_streak_sync_key, true, expires_in: MANUAL_STREAK_SYNC_THROTTLE)
    Rails.cache.write(streak_sync_throttle_key, true, expires_in: STREAK_SYNC_THROTTLE)
    StreakActivity.sync_for_user!(self)
  end

  # This week, Sunday to Saturday, and which days you hit your 20 minutes.
  def streak_week(today: streak_today_date)
    week = today.beginning_of_week(:sunday)..today.end_of_week(:sunday)
    completed = streak_activities.for_range(week).select(&:completed?).map(&:activity_date).to_set
    week.map do |date|
      { date:, letter: Date::ABBR_DAYNAMES[date.wday][0], today: date == today, completed: completed.include?(date),
        skipped: date == streak_skip_used_on }
    end
  end

  private
    def streak_sync_throttle_key
      "streak_sync:#{id}"
    end

    def manual_streak_sync_key
      "streak_sync_manual:#{id}"
    end

    # Your streak and the day your skip day covered, if it has: from your first day on, a day you hit 20 minutes adds
    # one, and a day you missed ends it, unless you have a skip day to cover it. You get one the first time a streak
    # reaches it, and keep it until you need it.
    def calculate_current_streak
      today = streak_today_date
      dates = streak_activities.completed.where(activity_date: ..today).pluck(:activity_date).to_set
      return [ 0, nil ] if dates.empty?

      skip_at = Reward.definition("skip_day")[:days]
      count, skip, skipped_on = 0, false, nil
      (dates.min..today).each do |date|
        if dates.include?(date)
          count += 1
          skip = true if count >= skip_at && skipped_on.nil?
        elsif date == today
          # Today isn't over.
        elsif skip
          skip, skipped_on = false, date
        else
          count = 0
        end
      end
      [ count, skipped_on ]
    end
end
