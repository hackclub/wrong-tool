require "test_helper"

class Admin::MetricsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
    MetricSnapshot.create!(day: Date.new(2026, 10, 6), key: "signed_in", value: 10)
    MetricSnapshot.create!(day: Date.new(2026, 10, 7), key: "signed_in", value: 14)
    MetricSnapshot.create!(day: Date.new(2026, 10, 7), key: "hours_day", value: 2.5)
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see each number by day, with the day's change on totals" do
    sign_in_as(users(:orpheus))
    get admin_metrics_path

    assert_response :success
    assert_select "thead th", text: "Oct 6"
    assert_select "tr", text: /Signed in\s*10\s*14\s*\+4/
    assert_select "tr", text: /Hours that day\s*—\s*2\.5/
  end

  test "nobody else can see it" do
    get admin_metrics_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id)
      post "/auth/hackclub"
      follow_redirect!
    end
end
