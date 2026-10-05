# One message Clippy sent someone on Slack, and whether they built afterwards. Every send is logged with the odds the
# bandit picked it at (propensity), so we can judge other policies against this log later.
#
# Every 15 minutes (NudgeDeliveryJob), anyone whose local time just reached the slot for when they said they'd build
# gets at most one: a fixed one if anything applies (Nudge::Fixed), otherwise whatever the bandit picks
# (Nudge::Bandit). Hourly (NudgeScoringJob), each one whose window has closed is scored on whether they built.
# What it says is Nudge::Copy, the Slack message is Nudge::Message, and its links are NudgeLinksController.
class Nudge < ApplicationRecord
  # Only bandit nudges are learned from. The rest always send when they apply.
  KINDS = %w[bandit setup milestone program streak_saver].freeze

  # Building this long after a nudge counts as it working. Same as what keeps a streak going.
  REWARD_MINUTES = 20
  REWARD_WINDOW = 6.hours
  # Stopping Clippy's messages from a nudge counts as this many failures.
  OPT_OUT_PENALTY = -5

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

  # The tracked links: /n/<token> goes where the button says, /n/<token>/stop stops Clippy's messages.
  has_secure_token :token

  validates :kind, inclusion: { in: KINDS }

  scope :bandit, -> { where(kind: "bandit") }
  scope :delivered, -> { where(delivered: true) }
  scope :scored, -> { where.not(reward: nil) }
  scope :unscored, -> { delivered.where(reward: nil) }

  # Everyone whose slot it is (with a timezone, on Slack, and not muted), one at a time so one person's trouble
  # doesn't stop the rest.
  def self.deliver_due(now = Time.current)
    User.joins(:project).includes(:project).where.not(timezone: nil).where.not(slack_id: [ nil, "" ])
        .where(slack_muted_at: nil, slack_dm_failed_at: nil).find_each do |user|
      deliver_to(user, now)
    rescue => error
      Rails.error.report(error, context: { user_id: user.id })
    end
  end

  # Their nudge, if it's their slot and they should get one. Their hours are brought up to date first.
  def self.deliver_to(user, now = Time.current)
    context = Nudge::Context.new(user, now)
    return unless context.in_slot?

    context.refresh!
    return unless context.may_nudge?

    nudge = Nudge::Fixed.for(context) || Nudge::Bandit.nudge_for(context)
    nudge&.deliver!(context.vars)
    nudge
  end

  def self.score_due(now = Time.current)
    unscored.where(sent_at: ..now - REWARD_WINDOW).find_each do |nudge|
      nudge.score!
    rescue Hackatime::Unavailable
      # Tried again next hour.
    end
  end

  def window_closes_at
    sent_at + REWARD_WINDOW
  end

  # 1 if they built REWARD_MINUTES in the window, 0 if not, OPT_OUT_PENALTY if this nudge made them stop Clippy's
  # messages.
  def score!
    reward =
      if opted_out_at then OPT_OUT_PENALTY
      elsif built_seconds >= REWARD_MINUTES * 60 then 1
      else 0
      end
    update!(reward:, rewarded_at: Time.current)
  end

  # Time on their linked Hackatime projects in the window. Nothing linked, or Hackatime not linked any more, is none.
  def built_seconds
    project = user.project
    return 0 unless project&.tracking?

    Hackatime.seconds_between(user, project.hackatime_projects, sent_at..window_closes_at)
  rescue Hackatime::NotLinked, Hackatime::Expired
    0
  end

  # A DM from Clippy's bot. If the bot can't DM them, nothing more is tried.
  def deliver!(vars)
    self.variant, self.text, self.mood, self.mood_text = Nudge::Copy.render(self, vars)
    save! # for the token in its links
    message = SlackBot.dm(user.slack_id, text:, blocks: Nudge::Message.new(self).blocks)
    user.update!(slack_dm_failed_at: Time.current) if message.nil? && Rails.configuration.x.slack_configured
    update!(delivered: message.present?, slack_channel: message&.channel, slack_ts: message&.ts, sent_at: Time.current)
    capture("nudge_sent") if delivered
  end

  def link_url = "#{Rails.configuration.x.app_url}/n/#{token}"
  def stop_url = "#{Rails.configuration.x.app_url}/n/#{token}/stop"

  # Where the button goes, past the tracked link.
  def destination_url
    case Nudge::Copy.link_for(arm).last
    when :slack then "https://hackclub.slack.com/archives/#{Program::SLACK_CHANNEL_ID}"
    else "#{Rails.configuration.x.app_url}/project" # Linking Hackatime and adding a repo are on the project page too.
    end
  end

  # Someone clicked the button. Counted every time, but the first click is the one that matters.
  def clicked!
    self.class.where(id:).update_all([ "clicks = clicks + 1, clicked_at = COALESCE(clicked_at, ?)", Time.current ])
    reload
  end

  # What PostHog gets with this nudge's events.
  def analytics_properties
    { nudge_id: id, kind:, arm:, variant:, mood:, bucket:, holdout:, propensity: }
  end

  def capture(event, properties = {})
    return unless Rails.configuration.x.posthog_configured
    PostHog.capture(distinct_id: user.posthog_distinct_id, event:, properties: analytics_properties.merge(properties))
  end
end
