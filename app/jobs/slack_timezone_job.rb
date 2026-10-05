# Someone's timezone from their Slack profile, for when their browser hasn't told us (see
# ApplicationController#remember_timezone). The browser wins whenever it does. Needs the bot's users:read scope.
class SlackTimezoneJob < ApplicationJob
  retry_on Slack::Web::Api::Errors::TooManyRequestsError, wait: 30.seconds, attempts: 3

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil? || user.slack_id.blank? || user.timezone.present?
    return Rails.logger.info("Slack (not configured): would look up #{user.slack_id}'s timezone") unless Rails.configuration.x.slack_configured

    user.remember_timezone(Slack::Web::Client.new.users_info(user: user.slack_id).dig("user", "tz"))
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
  rescue Slack::Web::Api::Errors::SlackError => error
    Rails.logger.warn("Looking up #{user.slack_id}'s Slack timezone failed: #{error.message}")
  end
end
