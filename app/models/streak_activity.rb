# How long someone built on one streak day, from Hackatime. Only time on the Hackatime projects linked to their
# project counts, and a day counts towards the streak at DAILY_GOAL_SECONDS. Days run 2am to 2am in their timezone,
# so building past midnight still counts for the night before. (From Stardance's streaks.)
class StreakActivity < ApplicationRecord
  DAILY_GOAL_SECONDS = 20 * 60

  belongs_to :user

  validates :activity_date, presence: true, uniqueness: { scope: :user_id }
  validates :coded_seconds, numericality: { greater_than_or_equal_to: 0 }

  scope :completed, -> { where(coded_seconds: DAILY_GOAL_SECONDS..) }
  scope :for_range, ->(range) { where(activity_date: range) }

  def completed?
    coded_seconds >= DAILY_GOAL_SECONDS
  end

  class << self
    # Rewrites every day since the day before the last sync (or since Hackatime time started counting) from
    # Hackatime's heartbeat spans, then the streak. Nothing happens without Hackatime linked and projects picked.
    def sync_for_user!(user)
      project = user.project
      return unless project&.tracking?

      today = streak_date_for(Time.current, user.timezone)
      synced_on = streak_date_for(user.streak_synced_at, user.timezone) - 1 if user.streak_synced_at
      start_date = [ synced_on || Program::HACKATIME_START, Program::HACKATIME_START ].max

      # Hackatime bounds spans by its own calendar days (midnight to midnight, its time), while streak days run 2am
      # to 2am in yours: so it's asked for a day either side, or tonight's building would be tomorrow by its clock
      # and left out until the next sync.
      spans = Hackatime.heartbeat_spans(user, project.hackatime_projects, start_date: start_date - 1, end_date: today + 2)
      daily_seconds = bucket_spans_by_streak_day(spans, user.timezone)

      (start_date..today).each do |date|
        seconds = daily_seconds.fetch(date, 0)
        record = find_or_initialize_by(user_id: user.id, activity_date: date)
        next if record.persisted? && record.coded_seconds == seconds
        record.update!(coded_seconds: seconds)
      end

      user.update_column(:streak_synced_at, Time.current)
      user.recalculate_streak!
    end

    def streak_date_for(time, timezone)
      (time.in_time_zone(timezone.presence || "UTC") - 2.hours).to_date
    end

    private
      # Seconds per streak day. A span across 2am is split between the two days.
      def bucket_spans_by_streak_day(spans, timezone)
        tz = timezone.presence || "UTC"
        buckets = Hash.new(0)

        spans.each do |span|
          duration = span["duration"].to_f
          next if duration <= 0

          start_local = Time.at(span["start_time"].to_f).in_time_zone(tz)
          end_local = Time.at(span["end_time"].to_f).in_time_zone(tz)

          if (start_local - 2.hours).to_date == (end_local - 2.hours).to_date
            buckets[(start_local - 2.hours).to_date] += duration.round
          else
            remaining = duration
            cursor = start_local

            while remaining > 0
              day = (cursor - 2.hours).to_date
              next_day = day + 1.day
              next_boundary = ActiveSupport::TimeZone[tz].local(next_day.year, next_day.month, next_day.day, 2, 0, 0)
              secs = [ next_boundary - cursor, remaining ].min
              buckets[day] += secs.round
              remaining -= secs
              cursor = next_boundary
            end
          end
        end

        buckets
      end
  end
end
