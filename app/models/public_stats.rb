# The numbers on the public stats page (/stats): totals across everyone, never anyone on their own. Any group of
# fewer than MIN_GROUP people (a tool, a day, a step) shows as "<3" instead, hours included, so a small number can't
# point at someone. Hours are from everyone's synced streak days (StreakActivity), so they lag Hackatime a little.
class PublicStats
  MIN_GROUP = 3
  CACHE_FOR = 10.minutes

  TOOL_LABELS = { "spreadsheet" => "Spreadsheets", "figma" => "Figma", "email" => "Email", "ssh" => "SSH",
                  "shaders" => "Shaders", "other" => "Something else" }.freeze
  # Streak lengths, grouped.
  STREAK_GROUPS = { "1 day" => 1..1, "2 days" => 2..2, "3–4" => 3..4, "5–6" => 5..6, "7–9" => 7..9, "10+" => 10.. }.freeze

  def self.cached
    Rails.cache.fetch("public_stats/v1", expires_in: CACHE_FOR) { new.to_h }
  end

  # A count, or nil when it's too few people to show.
  def self.shown(count) = count >= MIN_GROUP ? count : nil

  def to_h
    { generated_at: Time.current, day: program_day, days: Program::DATES.count, totals:, funnel:, daily:, tools:, streaks: }
  end

  private
    def program_day
      (Date.current - Program::DATES.begin).to_i + 1
    end

    # Seconds built per person since Hackatime time started counting.
    def seconds_by_user
      @seconds_by_user ||= StreakActivity.where(activity_date: Program::HACKATIME_START..).group(:user_id).sum(:coded_seconds)
    end

    def users_with_hours(hours) = seconds_by_user.count { |_, seconds| seconds >= hours * 3600 }

    def totals
      builders = seconds_by_user.count { |_, seconds| seconds.positive? }
      {
        builders: shown(Project.count),
        hours: ((seconds_by_user.values.sum / 3600.0).round if builders >= MIN_GROUP),
        shipped: shown(Ship.distinct.count(:project_id)),
        handhelds: shown(users_with_hours(Program::HOURS_PER_REWARD))
      }
    end

    # Signed in to shipped, each step with how many got there.
    def funnel
      linked = User.joins(:project).where.not(hackatime_uid: nil).where.not(hackatime_access_token: nil)
      steps = {
        "Signed in" => User.count,
        "Pledged" => Project.count,
        "Linked Hackatime" => linked.count,
        "Picked their Hackatime project" => linked.where("json_array_length(projects.hackatime_projects) > 0").count,
        "Built their first 20 minutes" => StreakActivity.completed.distinct.count(:user_id),
        "Reached #{Program::HOURS_PER_REWARD / 2} hours" => users_with_hours(Program::HOURS_PER_REWARD / 2.0),
        "Reached #{Program::HOURS_PER_REWARD} hours" => users_with_hours(Program::HOURS_PER_REWARD),
        "Shipped" => Ship.distinct.count(:project_id)
      }
      first = steps.values.first
      steps.map { |label, count| { label:, count: shown(count), share: (count.fdiv(first) if first >= MIN_GROUP && count >= MIN_GROUP) } }
    end

    # Hours built each day of wrong tool, by everyone who built that day.
    def daily
      days = StreakActivity.where(activity_date: Program::DATES, coded_seconds: 1..).group(:activity_date)
                           .pluck(:activity_date, Arel.sql("SUM(coded_seconds)"), Arel.sql("COUNT(DISTINCT user_id)"))
                           .to_h { |date, seconds, builders| [ date, [ seconds, builders ] ] }
      Program::DATES.map do |date|
        seconds, builders = days.fetch(date, [ 0, 0 ])
        { date:, future: date > Date.current, builders: shown(builders),
          hours: ((seconds / 3600.0).round(1) if builders >= MIN_GROUP) }
      end
    end

    # How many people are building in each wrong tool, and how long they've built.
    def tools
      counts = Project.group(:tool).count
      seconds = StreakActivity.where(activity_date: Program::HACKATIME_START..).joins(user: :project).group("projects.tool").sum(:coded_seconds)
      TOOL_LABELS.map do |tool, label|
        count = counts.fetch(tool, 0)
        { label:, builders: shown(count), hours: ((seconds.fetch(tool, 0) / 3600.0).round if count >= MIN_GROUP) }
      end
    end

    def streaks
      streakers = User.where(current_streak: 1..)
      lengths = streakers.pluck(:current_streak)
      {
        on_streak: shown(lengths.size),
        longest: (lengths.max if lengths.size >= MIN_GROUP),
        pairs: shown(Pair.count),
        groups: STREAK_GROUPS.map { |label, range| { label:, people: shown(lengths.count { |days| range.cover?(days) }) } }
      }
    end

    def shown(count) = self.class.shown(count)
end
