# What you earn for keeping a streak or logging hours, and what a pair earns building side by side. A row means it's
# been earned: streak and hours rewards belong to a user, pair rewards to a pair. Each is earned once, and the desktop background only once
# ever, by the first pair to get there. Earning one tells whoever earned it on Slack (RewardNotifier).
class Reward < ApplicationRecord
  # Days in a row of 20 minutes.
  STREAK = [
    { key: "gold_star", days: 3, label: "Gold star for Clippy", about: "Clippy wears a star on your sheet." },
    { key: "flame", days: 5, label: "Flame on the leaderboard", about: "A 🔥 next to your name while your streak lasts." },
    { key: "skip_day", days: 7, label: "1 skip day", about: "Miss a day and your streak doesn't reset." },
    { key: "streak_shoutout", days: 10, label: "Shoutout in #wrong", about: "We post your game in the channel." }
  ].freeze

  # Hours logged on your linked Hackatime projects since the program started. The milestone on the project page's
  # hours track (Program::MILESTONES): the handheld and the bonus past it are claimed by shipping, not awarded here.
  HOURS = [
    { key: "hours_shoutout", hours: Program::MILESTONES.key("shoutout"), label: "Shoutout in #wrong", about: "We post your game in the channel." }
  ].freeze

  # Pair weeks are program weeks you both log Pair::WEEKLY_HOURS in. The desktop background goes to the first pair
  # where you've both logged DESKTOP_HOURS.
  DESKTOP_HOURS = 10
  PAIR = [
    { key: "pair_listed", when: "First pomodoro together", short: "Pomodoro", label: "Shown as a pair on the leaderboard",
      about: "Your names appear together." },
    { key: "stickers", weeks: 1, when: "1 pair week", short: "1 wk", label: "Sticker sheet each",
      about: "Sent with your handheld." },
    { key: "pair_shoutout", weeks: 2, when: "2 pair weeks", short: "2 wk", label: "A mention in #wrong",
      about: "We share both of your games." },
    { key: "desktop", when: "First pair to #{DESKTOP_HOURS}h each", short: "#{DESKTOP_HOURS}h", label: "Pick Kartikey's desktop background",
      about: "For the first pair only." }
  ].freeze

  KEYS = (STREAK + HOURS + PAIR).map { |reward| reward[:key] }.freeze

  belongs_to :user, optional: true
  belongs_to :pair, optional: true

  validates :key, inclusion: { in: KEYS }
  validate :belongs_to_one

  after_create_commit -> { RewardNotifier.earned(self) unless Reward.quiet }

  # Rewards earned inside the block don't tell anyone, so a backfill can post one roundup instead of a flood
  # (bin/rails rewards:backfill_hours_shoutouts).
  thread_mattr_accessor :quiet, default: false

  def self.quietly
    self.quiet = true
    yield
  ensure
    self.quiet = false
  end

  def self.definition(key) = (STREAK + HOURS + PAIR).find { |reward| reward[:key] == key }

  # Who has the desktop background, if anyone does yet.
  def self.desktop_pair = find_by(key: "desktop")&.pair

  # Every streak reward your streak has reached.
  def self.award_streak!(user)
    STREAK.each { |reward| earn(user:, key: reward[:key]) if user.current_streak >= reward[:days] }
  end

  # Every hours reward your logged hours have reached. Nothing without Hackatime linked and projects picked, since
  # hours only count from there.
  def self.award_hours!(user)
    return unless user.project&.tracking?
    hours = user.hours_in(Program::HACKATIME_START..)
    HOURS.each { |reward| earn(user:, key: reward[:key]) if hours >= reward[:hours] }
  end

  # Every pair reward the pair has reached (bar the first pomodoro, which comes from joining one).
  def self.award_pair!(pair)
    PAIR.each { |reward| earn(pair:, key: reward[:key]) if reward[:weeks] && pair.pair_weeks >= reward[:weeks] }
    earn(pair:, key: "desktop") if pair.desktop_ready? && !exists?(key: "desktop")
  end

  # Your first pomodoro together, once the second of you joins it.
  def self.award_pomodoro!(pair)
    earn(pair:, key: "pair_listed")
  end

  def self.earn(**attributes)
    find_or_create_by!(**attributes)
  rescue ActiveRecord::RecordNotUnique
    # Earned at the same moment somewhere else (or someone else got the desktop first).
  end
  private_class_method :earn

  def definition = self.class.definition(key)

  # Who it's for: you, or both of you.
  def users = pair ? pair.projects.map(&:user) : [ user ]

  private
    def belongs_to_one
      errors.add(:base, "belongs to a user or a pair") unless user.nil? ^ pair.nil?
    end
end
