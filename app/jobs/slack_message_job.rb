# Posts one message from Clippy's bot: to someone's Slack ID, which DMs them, or to a channel's ID. `text` is what
# shows in notifications; the message itself is app/views/slack/message.slack_message.slocks, with a button if
# there's a `link` ([ label, url ]). A DM is noted as Clippy's latest to them (User#slack_dmed!), which spaces his
# messages out. (Like Stardance's SendSlackDmJob.)
class SlackMessageJob < ApplicationJob
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 3

  def perform(channel, text, link: nil)
    return Rails.logger.info("Slack (not configured) to #{channel}: #{text}") unless Rails.configuration.x.slack_configured

    rendered = ApplicationController.renderer.new.render(template: "slack/message", formats: [ :slack_message ], locals: { text:, link: })
    Slack::Web::Client.new.chat_postMessage(channel:, text:, unfurl_links: false, **JSON.parse(rendered, symbolize_names: true))
    User.find_by(slack_id: channel)&.slack_dmed!
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    # They left the workspace, or can't be DMed: nothing to do but note it.
    Rails.logger.warn("Slack message to #{channel} failed: #{error.message}")
  end
end
