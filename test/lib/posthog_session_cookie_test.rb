require "test_helper"

class PosthogSessionCookieTest < ActiveSupport::TestCase
  setup do
    @token = "phc_test"
    @original_token = Rails.configuration.x.posthog_project_token
    Rails.configuration.x.posthog_project_token = @token
  end

  teardown { Rails.configuration.x.posthog_project_token = @original_token }

  test "fills the session id in from posthog-js's cookie" do
    assert_equal "session-1", session_id_for(cookie: sesid(1.minute.ago, "session-1"))
  end

  test "keeps a session id the browser sent" do
    assert_equal "from-header", session_id_for(cookie: sesid(1.minute.ago, "session-1"), header: "from-header")
  end

  test "leaves out a session posthog-js would have ended" do
    assert_nil session_id_for(cookie: sesid(31.minutes.ago, "session-1"))
  end

  test "ignores a missing or broken cookie" do
    assert_nil session_id_for(cookie: nil)
    assert_nil session_id_for(cookie: "not json")
    assert_nil session_id_for(cookie: { "distinct_id" => "x" }.to_json)
  end

  private

  def sesid(last_activity, session_id)
    { "$sesid" => [ (last_activity.to_f * 1000).to_i, session_id, (last_activity.to_f * 1000).to_i ] }.to_json
  end

  def session_id_for(cookie:, header: nil)
    env = Rack::MockRequest.env_for("/")
    env["HTTP_COOKIE"] = "ph_#{@token}_posthog=#{ERB::Util.url_encode(cookie)}" if cookie
    env[PosthogSessionCookie::HEADER] = header if header
    seen = nil
    PosthogSessionCookie.new(->(e) { seen = e[PosthogSessionCookie::HEADER]; [ 200, {}, [] ] }).call(env)
    seen
  end
end
