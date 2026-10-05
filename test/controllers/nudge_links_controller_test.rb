require "test_helper"

class NudgeLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "progress", mood: "proud",
                                            text: "you're 35% of the way to a miyoo mini plus.")
  end

  test "the button counts the click and goes where it said" do
    get nudge_link_path(@nudge.token)
    assert_redirected_to "#{Rails.configuration.x.app_url}/project"

    get nudge_link_path(@nudge.token)
    @nudge.reload
    assert_equal 2, @nudge.clicks
    assert @nudge.clicked_at
  end

  test "a button to #wrong goes to #wrong" do
    @nudge.update!(arm: "social")
    get nudge_link_path(@nudge.token)
    assert_redirected_to "https://hackclub.slack.com/archives/#{Program::SLACK_CHANNEL_ID}"
  end

  test "a link that doesn't exist goes home" do
    get nudge_link_path("nope")
    assert_redirected_to root_path
  end

  test "stopping asks first, since links get opened ahead of time" do
    get nudge_stop_path(@nudge.token)

    assert_response :success
    assert_select "h1", "Stop Clippy's messages?"
    assert_nil users(:orpheus).reload.slack_muted_at
  end

  test "stopping mutes Clippy and counts against that nudge, and you can change your mind" do
    post nudge_stop_path(@nudge.token)
    follow_redirect!
    assert_select "h1", "Clippy won't message you anymore."
    assert users(:orpheus).reload.slack_muted_at
    assert @nudge.reload.opted_out_at

    delete nudge_stop_path(@nudge.token)
    follow_redirect!
    assert_select "h1", "Stop Clippy's messages?"
    assert_nil users(:orpheus).reload.slack_muted_at
    assert_nil @nudge.reload.opted_out_at
  end
end
