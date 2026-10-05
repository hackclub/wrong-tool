# Clippy's Slack bot (see SlackMessageJob), all from Rails credentials (bin/rails credentials:edit):
#
#   slack:
#     bot_token: xoxb-…   # scopes: chat:write, channels:manage (and groups:write for private channels), users:read
#     kartikey_id: U…     # Kartikey, for the desktop background
#
# The channels are in Program::SLACK_CHANNEL_IDS, and the bot needs to be in them.
#
# Without a bot token nothing's sent, only logged.
slack = Rails.application.credentials.slack || {}

Slack.configure { |config| config.token = slack[:bot_token] }
Rails.application.config.x.slack_configured = slack[:bot_token].present?
Rails.application.config.x.slack_kartikey_id = slack[:kartikey_id]

missing = %i[bot_token kartikey_id].select { |key| slack[key].blank? }
if missing.any? && !Rails.env.test?
  Rails.logger.warn("Slack credentials missing (#{missing.map { |key| "slack.#{key}" }.join(", ")}): Slack messages are only logged")
end

# Where links in Slack messages go.
Rails.application.config.x.app_url = ENV.fetch("APP_URL", "https://wrong.hackclub.com")
