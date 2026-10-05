posthog = ->(key) { Rails.application.credentials.dig(:posthog, key) || ENV["POSTHOG_#{key.upcase}"] }
posthog_api_key = posthog.(:project_token)
posthog_host = posthog.(:host)
posthog_missing_variable = {
  "posthog.project_token" => posthog_api_key,
  "posthog.host" => posthog_host
}.find { |_, value| value.blank? }&.first
# Only production sends anything, so dev and test traffic stays out of the project's data.
Rails.application.config.x.posthog_configured = Rails.env.production? && posthog_missing_variable.nil?
# The browser sends events too (posthog-js, see app/views/layouts/_posthog.html.erb), to the same project.
Rails.application.config.x.posthog_project_token = posthog_api_key
Rails.application.config.x.posthog_host = posthog_host

if Rails.application.config.x.posthog_configured
  PostHog.init do |config|
    config.api_key = posthog_api_key
    config.host = posthog_host
  end

  PostHog::Rails.configure do |config|
    config.auto_capture_exceptions = true
    config.report_rescued_exceptions = true
    config.auto_instrument_active_job = true
    config.capture_user_context = true
    config.current_user_method = :current_user
    config.user_id_method = :posthog_distinct_id
  end
end
