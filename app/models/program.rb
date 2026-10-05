# wrong tool itself: when it runs, and how many hours earn a handheld.
module Program
  # Launches Oct 6 and runs for two weeks.
  DATES = Date.new(2026, 10, 6)..Date.new(2026, 10, 20)
  HOURS_PER_REWARD = 10
  # Hackatime time from this day on counts: only projects worked on since then can be linked.
  HACKATIME_START = Date.new(2026, 10, 6)
  # What each milestone of logged hours gets you, up to the most there is.
  MILESTONES = { 5 => "shoutout", 10 => "handheld", 20 => "+$85" }.freeze
  # Two weeks, for weekly hours and pair weeks: the first runs to Sunday, the second to the end.
  WEEKS = [ DATES.begin..Date.new(2026, 10, 12), Date.new(2026, 10, 13)..DATES.end ].freeze
  # wrong tool's Slack channels: #wrong, for shoutouts, and everyone's added to both when they first sign in.
  SLACK_CHANNEL_ID = "C0C5UHLAAP5"
  SLACK_CHANNEL_IDS = [ SLACK_CHANNEL_ID, "C0C60KQ0XLJ" ].freeze
  # We play everyone's game live on stream, at 7pm.
  PLAY_PARTY_ON = Date.new(2026, 10, 8)

  # The program week a day's in, or nil outside the program.
  def self.week_of(date)
    WEEKS.find { |week| week.cover?(date) }
  end
end
