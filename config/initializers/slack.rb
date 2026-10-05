# Clippy's Slack bot (see SlackMessageJob): its token, #wrong's channel ID for shoutouts, and Kartikey's Slack ID
# for the desktop background. Credentials (slack: bot_token, channel_id, kartikey_id) or the environment. Without a
# token nothing's sent, only logged.
slack = ->(key) { Rails.application.credentials.dig(:slack, key) || ENV["SLACK_#{key.upcase}"] }

Slack.configure { |config| config.token = slack.(:bot_token) }
Rails.application.config.x.slack_configured = slack.(:bot_token).present?
Rails.application.config.x.slack_channel_id = slack.(:channel_id)
Rails.application.config.x.slack_kartikey_id = slack.(:kartikey_id)
# Where links in Slack messages go.
Rails.application.config.x.app_url = ENV.fetch("APP_URL", "https://wrong.hackclub.com")
