require "test_helper"

class SlackProfileJobTest < ActiveJob::TestCase
  setup do
    @configured, Rails.configuration.x.slack_configured = Rails.configuration.x.slack_configured, true
    @users_info = Slack::Web::Client.instance_method(:users_info)
  end

  teardown do
    Rails.configuration.x.slack_configured = @configured
    Slack::Web::Client.define_method(:users_info, @users_info)
  end

  def slack_profile(display_name:, real_name: "Ana Lovelace", tz: "Europe/London")
    user = Slack::Messages::Message.new(user: { tz:, real_name:, profile: { display_name:, real_name: } })
    Slack::Web::Client.define_method(:users_info) { |**| user }
  end

  test "takes your Slack display name, and your timezone if your browser hasn't said" do
    slack_profile(display_name: " pixel ana ")
    SlackProfileJob.perform_now(users(:ana).id)

    assert_equal "pixel ana", users(:ana).reload.slack_display_name
    assert_equal "Europe/London", users(:ana).timezone
  end

  test "with no display name, never falls back to your real name" do
    users(:ana).update!(timezone: "Asia/Tokyo")
    slack_profile(display_name: "")
    SlackProfileJob.perform_now(users(:ana).id)

    assert_nil users(:ana).reload.slack_display_name
    assert_equal "Anonymous #{users(:ana).animal.capitalize}", users(:ana).public_name
    assert_equal "Asia/Tokyo", users(:ana).timezone, "the browser's timezone wins"
  end
end
