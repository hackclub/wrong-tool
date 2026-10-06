posthog = ->(key) { Rails.application.credentials.dig(:posthog, key) || ENV["POSTHOG_#{key.upcase}"] }
posthog_api_key = posthog.(:project_token)
posthog_host = posthog.(:host)
posthog_missing_variable = {
  "POSTHOG_PROJECT_TOKEN" => posthog_api_key,
  "POSTHOG_HOST" => posthog_host
}.find { |_, value| value.blank? }&.first

if posthog_missing_variable && Rails.env.development?
  raise KeyError, "#{posthog_missing_variable} variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once #{posthog_missing_variable} is configured"
end

Rails.application.config.x.posthog_configured = posthog_missing_variable.nil?
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

  require "opentelemetry/sdk"
  require "opentelemetry/exporter/otlp"
  require "opentelemetry/sdk/logs"
  require "opentelemetry/exporter/otlp_logs"

  posthog_log_exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(
    endpoint: "#{posthog_host}/i/v1/logs",
    headers: { "authorization" => "Bearer #{posthog_api_key}" }
  )
  OpenTelemetry::SDK.configure do |config|
    config.add_log_record_processor(
      OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(posthog_log_exporter)
    )
  end
  Rails.application.config.x.posthog_log_logger = OpenTelemetry.logger_provider.logger(name: "wrong_tool.posthog")
  Rails.application.config.x.posthog_log_capture_configured = true
else
  Rails.application.config.x.posthog_log_capture_configured = false
end
