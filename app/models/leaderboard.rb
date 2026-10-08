# Everyone who's set up, ranked by hours this week (or streak): what the leaderboard page, the stairs on your project
# page and Clippy's leaderboard nudges all read from, so they agree. Ties go to whoever pledged first.
#
# Once a day (LeaderboardSnapshotJob) everyone's week rank is noted on their project, so the board can show who's
# moved since yesterday and Clippy can say who passed you. A snapshot from a different program week is ignored:
# week hours start over on Monday, so Monday has no arrows.
module Leaderboard
  SORTS = %w[week streak].freeze

  Place = Data.define(:project, :rank, :above) do
    def user = project.user

    # Hours this week between you and the one above you, in minutes. Nothing if you're first.
    def gap_minutes
      ((above.hours_this_week - project.hours_this_week) * 60).round if above
    end

    # Places you've moved since the last snapshot: up is positive, down negative, nil without a snapshot this week.
    def change
      was = project.week_rank
      was - rank if was && project.week_rank_on && Program.week_of(project.week_rank_on) == Program.week_of(Date.current)
    end
  end

  # Set-up projects in order, with their users (and screenshots, for the board).
  def self.ranked(sort: "week", projects: Project.includes(:user, screenshot_attachment: :blob))
    key = sort == "streak" ? :streak : :hours_this_week
    projects.select(&:set_up?).sort_by { |project| [ -project.public_send(key), project.id ] }
  end

  # Everyone's place, in order.
  def self.places(sort: "week", projects: nil)
    ranked = projects ? ranked(sort:, projects:) : ranked(sort:)
    ranked.map.with_index(1) { |project, rank| Place.new(project:, rank:, above: (ranked[rank - 2] if rank > 1)) }
  end

  # Your place this week, or nil until you're set up.
  def self.place_of(project)
    places.find { |place| place.project == project }
  end

  # Note everyone's week rank as of now (see Project#week_rank).
  def self.snapshot!(today = Date.current)
    places(projects: Project.includes(:user)).each do |place|
      place.project.update_columns(week_rank: place.rank, week_rank_on: today)
    end
  end
end
