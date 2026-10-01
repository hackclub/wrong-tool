# wrong tool itself: when it runs, and how many hours earn a handheld.
module Program
  DATES = Date.new(2026, 10, 2)..Date.new(2026, 10, 16)
  HOURS_PER_REWARD = 10
  # Hackatime time from this day on counts: only projects worked on since then can be linked.
  HACKATIME_START = Date.new(2026, 9, 25)
  # What each milestone of logged hours gets you, up to the most there is.
  MILESTONES = { 5 => "shoutout", 10 => "handheld", 20 => "+$85" }.freeze
  # We play everyone's game live on stream, at 7pm.
  PLAY_PARTY_ON = Date.new(2026, 10, 8)
end
