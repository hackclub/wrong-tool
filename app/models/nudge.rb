# PSEUDO CODE: a sketch of how Clippy's nudges will work. Nothing calls it yet, and the nudges table, the user
# columns below, Hackatime and SlackBot don't exist yet.
#
# One message Clippy sent someone, and whether they built afterwards. Every send is logged with the odds the bandit
# picked it at (propensity), so we can judge other policies against this log later.
#
# nudges (no migration yet):
#   user_id, channel (slack | email), kind (see KINDS), bucket ("behind/slack"), arm, variant (which copy),
#   propensity, holdout (bool), sent_at, delivered (bool), reward (1, 0 or OPT_OUT_PENALTY; nil until scored),
#   rewarded_at
#
# users also needs has_many :nudges, and:
#   timezone (IANA, like "America/New_York": from the browser at onboarding, falling back to Slack's users.info),
#   slack_dm_failed_at (the bot couldn't DM them, so email instead), slack_muted_at, email_unsubscribed_at
class Nudge < ApplicationRecord
  CHANNELS = %w[slack email].freeze
  # Only bandit nudges are learned from. The rest always send when they apply.
  KINDS = %w[bandit setup milestone program streak_saver].freeze

  # Building this long after a nudge counts as it working. Same as what keeps a streak going.
  REWARD_MINUTES = 20
  # Email gets read later than a Slack DM, so it gets longer to work.
  REWARD_WINDOW = { "slack" => 6.hours, "email" => 12.hours }.freeze
  # Muting Clippy or unsubscribing after a nudge counts as this many failures.
  OPT_OUT_PENALTY = -5

  # Shared across Slack and email.
  DAILY_CAP = 1
  WEEKLY_CAP = 5
  # Dramatic Clippy is a bit; it stops being funny the third time.
  DRAMATIC_CAP = 2

  # Local time. Nothing sends at or after QUIET_FROM or before QUIET_UNTIL, late night builders included.
  QUIET_FROM = 22
  QUIET_UNTIL = 8

  # Local send time for each build time. Weekend builders only hear from Clippy on Saturdays and Sundays.
  # TODO: a second bandit over sending at the slot vs an hour before it.
  SLOTS = { "after school" => "15:30", "evening" => "19:00", "late night" => "21:30", "weekends" => "11:00" }.freeze

  belongs_to :user

  scope :bandit, -> { where(kind: "bandit") }
  scope :scored, -> { where.not(reward: nil) }
  scope :unscored, -> { where(reward: nil, delivered: true) }

  # Run every 15 minutes. Anyone whose local time just reached their slot gets at most one nudge: a fixed one if
  # anything applies, otherwise whatever the bandit picks.
  def self.deliver_due(now = Time.current)
    User.joins(:project).where.not(timezone: nil).find_each do |user|
      context = Nudge::Context.new(user, now)
      next unless context.in_slot? && context.may_nudge?

      nudge = Nudge::Fixed.for(context) || Nudge::Bandit.nudge_for(context)
      nudge&.deliver!(context.vars)
    end
  end

  # Run hourly. Scores every nudge whose window has closed.
  def self.score_due(now = Time.current)
    unscored.find_each { |nudge| nudge.score! if nudge.window_closes_at <= now }
  end

  def window_closes_at
    sent_at + REWARD_WINDOW.fetch(channel)
  end

  def score!
    reward =
      if user.opted_out_between?(sent_at, window_closes_at) then OPT_OUT_PENALTY
      elsif Hackatime.minutes_for(user, sent_at..window_closes_at) >= REWARD_MINUTES then 1
      else 0
      end
    update!(reward:, rewarded_at: Time.current)
  end

  # Slack if the bot can DM them, email otherwise. A DM that fails falls back to email this time and from now on.
  def deliver!(vars)
    self.variant, text = Nudge::Copy.render(self, vars)
    if channel == "slack"
      self.delivered = SlackBot.dm(user.slack_id, text, button: Nudge::Copy.link_for(arm), mute_button: Nudge::Copy::SLACK_MUTE)
      unless delivered
        user.update!(slack_dm_failed_at: Time.current)
        self.channel = "email"
      end
    end
    if channel == "email"
      NudgeMailer.with(nudge: self, subject: Nudge::Copy.subject_for(self, vars), text:).nudge.deliver_later
      self.delivered = true
    end
    self.sent_at = Time.current
    save!
  end
end
