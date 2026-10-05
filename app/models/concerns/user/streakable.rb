# Your streak: days in a row you built at least 20 minutes on your linked Hackatime projects, kept up to date from
# Hackatime in the background. Today doesn't break it until it's over. (From Stardance's streaks.)
module User::Streakable
  extend ActiveSupport::Concern

  # How long a sync holds off the next one, so every page load doesn't ask Hackatime.
  STREAK_SYNC_THROTTLE = 15.minutes

  # How long hitting Refresh holds off the next one, so mashing it doesn't hammer Hackatime.
  MANUAL_STREAK_SYNC_THROTTLE = 20.seconds

  included do
    has_many :streak_activities, dependent: :destroy
  end

  def streak_today_date
    StreakActivity.streak_date_for(Time.current, timezone)
  end

  def recalculate_streak!
    update_column(:current_streak, calculate_current_streak)
  end

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
      update_columns(current_streak: 0, streak_synced_at: nil)
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
      { date:, letter: Date::ABBR_DAYNAMES[date.wday][0], today: date == today, completed: completed.include?(date) }
    end
  end

  private
    def streak_sync_throttle_key
      "streak_sync:#{id}"
    end

    def manual_streak_sync_key
      "streak_sync_manual:#{id}"
    end

    def calculate_current_streak
      today = streak_today_date
      dates = streak_activities.completed
        .where(activity_date: ..today)
        .order(activity_date: :desc)
        .limit(400)
        .pluck(:activity_date)
        .to_set
      date = dates.include?(today) ? today : today - 1.day
      count = 0
      count += 1 and date -= 1.day while dates.include?(date)
      count
    end
end
