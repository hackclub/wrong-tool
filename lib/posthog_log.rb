module PosthogLog
  class << self
    def info(message)
      emit(message, "INFO")
    end

    def warn(message)
      emit(message, "WARN")
    end

    private

    def emit(message, severity_text)
      return unless Rails.configuration.x.posthog_log_capture_configured

      Rails.configuration.x.posthog_log_logger.on_emit(
        severity_text:,
        body: message,
        attributes: { "log.source" => "posthog_integration" }
      )
    end
  end
end
