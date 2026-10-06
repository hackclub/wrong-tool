# Ties server-side PostHog events to the browser's session, so they can filter session recordings.
#
# posthog-rails puts a request's X-PostHog-Session-Id header on every event captured while handling it. posthog-js
# sends that header on fetches (tracing_headers in app/views/layouts/_posthog.html.erb), but not on plain page loads,
# non-Turbo form posts or redirects back from sign-in. For those, this fills the header in from the session id
# posthog-js keeps in its cookie.
class PosthogSessionCookie
  HEADER = "HTTP_X_POSTHOG_SESSION_ID"
  # posthog-js starts a new session after 30 minutes without activity.
  SESSION_IDLE_TIMEOUT = 30.minutes

  def initialize(app)
    @app = app
  end

  def call(env)
    if env[HEADER].blank? && (session_id = session_id_from_cookie(env))
      env[HEADER] = session_id
    end
    @app.call(env)
  end

  private

  def session_id_from_cookie(env)
    token = Rails.configuration.x.posthog_project_token
    return if token.blank?

    cookie = Rack::Request.new(env).cookies["ph_#{token}_posthog"]
    return if cookie.blank?

    # "$sesid" is [last activity (ms), session id, session start (ms)].
    last_activity_ms, session_id, _started_ms = JSON.parse(cookie)["$sesid"]
    return unless session_id.is_a?(String) && last_activity_ms.is_a?(Numeric)
    return if Time.at(last_activity_ms / 1000.0) < SESSION_IDLE_TIMEOUT.ago

    session_id
  rescue JSON::ParserError, TypeError, NoMethodError
    nil
  end
end
