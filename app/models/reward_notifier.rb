# Telling people on Slack they've earned a reward (Reward): a DM to each of you, and for shoutouts and the desktop
# background, a post in #wrong. Posts are a plain line about them, then how Clippy feels about it.
module RewardNotifier
  # The DM. %{buddy} is the other half of a pair.
  DMS = {
    "gold_star" => "3-day streak. Clippy now wears a gold star on your sheet.",
    "flame" => "5-day streak. You have a 🔥 next to your name on the leaderboard while your streak lasts.",
    "skip_day" => "7-day streak. You've earned a skip day: if you miss a day, your streak won't reset.",
    "streak_shoutout" => "10-day streak. We posted %{title} in #wrong.",
    "hours_shoutout" => "#{Program::MILESTONES.key("shoutout")} hours logged. We posted %{title} in #wrong.",
    "pair_listed" => "You and %{buddy} finished a pomodoro together, so you're shown as a pair on the leaderboard now.",
    "stickers" => "You and %{buddy} both logged #{Pair::WEEKLY_HOURS}h this week. You'll each get a sticker sheet with your handheld.",
    "pair_shoutout" => "You and %{buddy} both logged #{Pair::WEEKLY_HOURS}h in both weeks. We shared your games in #wrong.",
    "desktop" => "You and %{buddy} were the first pair to log #{Reward::DESKTOP_HOURS}h each, so you get to pick Kartikey's " \
                 "desktop background. Send %{kartikey} an image whenever you like."
  }.freeze

  # The post in #wrong, for the ones that have one.
  POSTS = {
    "streak_shoutout" => "%{you} has a 10-day streak, building %{title} in %{tool}.",
    "hours_shoutout" => ":yay: %{you} just logged #{Program::MILESTONES.key("shoutout")} hours on %{title}, built in %{tool}. " \
                        "halfway to a handheld.\n_clippy is doing a little dance. :dino-bbq:_",
    "pair_shoutout" => "%{you} and %{buddy} built together through both weeks of wrong tool: " \
                       "%{title} in %{tool}, and %{buddy_title} in %{buddy_tool}.",
    "desktop" => "%{you} and %{buddy} were the first pair to log #{Reward::DESKTOP_HOURS}h each. " \
                 "They'll pick Kartikey's desktop background."
  }.freeze

  # One post for a batch of hours shoutouts earned before the reward existed (bin/rails rewards:backfill_hours_shoutouts).
  ROUNDUP = ":yay: %{hours} hours logged since kickoff, by %{people}. halfway to a handheld, every one of them.\n" \
            "_clippy is overwhelmed. :cat-woah:_"

  def self.earned(reward)
    dm(reward)
    post(reward)
  end

  def self.dm(reward)
    projects = reward.users.map(&:project)
    projects.each do |project|
      next if project.user.slack_id.blank?
      vars = vars_for(project, (projects - [ project ]).first)
      SlackMessageJob.perform_later(project.user.slack_id, format(DMS.fetch(reward.key), vars), link: [ "Open wrong tool", project_url ])
    end
  end

  def self.post(reward)
    return unless POSTS.key?(reward.key)
    SlackMessageJob.perform_later(Program::SLACK_CHANNEL_ID, format(POSTS.fetch(reward.key), vars_for(*reward.users.map(&:project))))
  end

  # The DM each, then the one post naming everyone: "@a (*title*), @b (*title*) and @c (*title*)".
  def self.roundup_hours_shoutouts(rewards)
    return if rewards.empty?
    rewards.each { |reward| dm(reward) }
    people = rewards.map { |reward| "#{mention(reward.user.project)} (*#{reward.user.project.title}*)" }.to_sentence
    SlackMessageJob.perform_later(Program::SLACK_CHANNEL_ID, format(ROUNDUP, hours: Program::MILESTONES.key("shoutout"), people:))
  end

  def self.vars_for(project, buddy = nil)
    kartikey = Rails.configuration.x.slack_kartikey_id
    { you: mention(project), title: "*#{project.title}*", tool: project.tool_name,
      buddy: buddy ? mention(buddy) : "", buddy_title: buddy ? "*#{buddy.title}*" : "", buddy_tool: buddy&.tool_name.to_s,
      kartikey: kartikey.present? ? "<@#{kartikey}>" : "Kartikey" }
  end

  # Their @mention (Slack shows the name they chose there), or what everyone here sees them as if they're not on
  # Slack: never their real name, since #wrong is public.
  def self.mention(project)
    user = project.user
    user.slack_id.present? ? "<@#{user.slack_id}>" : user.public_name
  end

  def self.project_url = "#{Rails.configuration.x.app_url}/project"

  private_class_method :vars_for, :mention, :project_url
end
