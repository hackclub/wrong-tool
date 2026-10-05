# Adds someone to wrong tool's Slack channels the first time they sign in: #wrong and its sibling. Once it's worked,
# it's not tried again. (Like Stardance's InviteToSlackChannelJob.)
class JoinSlackChannelsJob < ApplicationJob
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 3

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil? || user.slack_id.blank? || user.slack_channels_joined_at
    return Rails.logger.info("Slack (not configured): would add #{user.slack_id} to #{Program::SLACK_CHANNEL_IDS.join(", ")}") unless Rails.configuration.x.slack_configured

    client = Slack::Web::Client.new
    Program::SLACK_CHANNEL_IDS.each do |channel|
      client.conversations_invite(channel:, users: user.slack_id)
    rescue Slack::Web::Api::Errors::SlackError => error
      raise unless error.message == "already_in_channel"
    end
    user.update_column(:slack_channels_joined_at, Time.current)
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    # Not tried again until they next sign in.
    Rails.logger.warn("Adding #{user.slack_id} to Slack channels failed: #{error.message}")
  end
end
