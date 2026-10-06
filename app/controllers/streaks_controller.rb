# Refresh on your streak card: asks Hackatime for your time now, rather than waiting for the next background sync.
class StreaksController < ApplicationController
  def update
    if current_user&.project
      current_user.sync_streak_now!
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "streak_refreshed"
      ) if Rails.configuration.x.posthog_configured
      PosthogLog.info("streak_refresh_completed")
    end
    redirect_to project_path
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    PosthogLog.warn("streak_refresh_unavailable")
    redirect_to project_path, flash: { streak_alert: "Couldn't reach Hackatime. Try again in a minute." }
  end
end
