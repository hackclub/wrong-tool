posthog = ->(key) { Rails.application.credentials.dig(:posthog, key) || ENV["POSTHOG_#{key.upcase}"] }
posthog_api_key = posthog.(:project_token)
posthog_host = posthog.(:host)
posthog_missing_variable = {
  "posthog.project_token" => posthog_api_key,
  "posthog.host" => posthog_host
}.find { |_, value| value.blank? }&.first
Rails.application.config.x.posthog_configured = posthog_missing_variable.nil?
# The browser sends events too (posthog-js, see app/views/layouts/_posthog.html.erb), to the same project.
Rails.application.config.x.posthog_project_token = posthog_api_key
Rails.application.config.x.posthog_host = posthog_host

if posthog_missing_variable
  if Rails.env.development?
    raise KeyError, "#{posthog_missing_variable} credential required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once #{posthog_missing_variable} is set in credentials (or #{posthog_missing_variable.tr(".", "_").upcase} in the environment)"
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
