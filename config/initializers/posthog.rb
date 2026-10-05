posthog_api_key = ENV["POSTHOG_PROJECT_TOKEN"]
posthog_host = ENV["POSTHOG_HOST"]
posthog_missing_variable = {
  "POSTHOG_PROJECT_TOKEN" => posthog_api_key,
  "POSTHOG_HOST" => posthog_host
}.find { |_, value| value.blank? }&.first
Rails.application.config.x.posthog_configured = posthog_missing_variable.nil?

if posthog_missing_variable
  if Rails.env.development?
    raise KeyError, "#{posthog_missing_variable} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once #{posthog_missing_variable} is configured"
  end
else
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
