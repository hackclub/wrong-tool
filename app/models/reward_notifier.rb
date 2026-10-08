# Telling people on Slack they've earned a reward (Reward): a DM to each of you, and for shoutouts and the desktop
# background, a post in #wrong. Posts are a plain line about them, then how Clippy feels about it, and go out at the
# reward's slot (Reward#announce_at), with the DM, so no two shoutouts land together. The emotes are Hack Club Slack's
# own (:yay:, :dino-bbq:, Clippy's :clippy-<mood>: and friends), so they only mean anything there.
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
    "streak_shoutout" => "🔥 %{you} has a 10-day streak, building %{title} in %{tool}.\n_:clippy-excited: clippy is vibrating. :ultrafastparrot:_",
    "hours_shoutout" => ":yay: %{you} just logged #{Program::MILESTONES.key("shoutout")} hours on %{title}, built in %{tool}. " \
                        "halfway to a handheld.\n_:clippy-proud: clippy is doing a little dance. :dino-bbq:_",
    "pair_shoutout" => ":partyparrot: %{you} and %{buddy} built together through both weeks of wrong tool: " \
                       "%{title} in %{tool}, and %{buddy_title} in %{buddy_tool}.\n_:clippy-emotional: clippy is crying. happy tears. :heavysob:_",
    "desktop" => ":blob_hype: %{you} and %{buddy} were the first pair to log #{Reward::DESKTOP_HOURS}h each. " \
                 "They'll pick Kartikey's desktop background.\n_:clippy-excited: clippy can't sit still. :blob-wiggle:_"
  }.freeze

  def self.posted?(key) = POSTS.key?(key)

  def self.earned(reward)
    projects = reward.users.map(&:project)
    messages = reward.announce_at ? SlackMessageJob.set(wait_until: reward.announce_at) : SlackMessageJob
    projects.each do |project|
      next if project.user.slack_id.blank?
      vars = vars_for(project, (projects - [ project ]).first)
      messages.perform_later(project.user.slack_id, format(DMS.fetch(reward.key), vars), link: [ "Open wrong tool", project_url ])
    end

    messages.perform_later(Program::SLACK_CHANNEL_ID, format(POSTS.fetch(reward.key), vars_for(*projects))) if posted?(reward.key)
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
