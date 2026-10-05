# Clippy's bot, for messages we keep track of (like Nudge): a DM's Slack message ({ channel:, ts: }), or nil if it
# didn't go. Posting to someone's Slack ID DMs them, without the bot needing im:write. Fire-and-forget messages go
# through SlackMessageJob instead.
module SlackBot
  def self.dm(slack_id, text:, blocks:)
    unless Rails.configuration.x.slack_configured
      Rails.logger.info("Slack (not configured) to #{slack_id}: #{text}")
      return
    end

    Slack::Web::Client.new.chat_postMessage(channel: slack_id, text:, blocks:, unfurl_links: false)
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    Rails.logger.warn("Slack DM to #{slack_id} failed: #{error.message}")
    nil
  end
end
