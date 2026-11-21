# Refresh on your streak card: asks Hackatime for your time now, rather than waiting for the next background sync.
# Either way the card says what happened, so a tap never looks like it did nothing.
class StreaksController < ApplicationController
  def update
    notice = nil
    if current_user&.project
      synced = current_user.sync_streak_now!
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "streak_refreshed",
        properties: { synced: }
      ) if Rails.configuration.x.posthog_configured
      PosthogLog.info("streak_refresh_completed")
      notice = synced ? "Synced with Hackatime." : "Already up to date. You can refresh again in a few seconds."
    end
    redirect_to project_path, flash: { streak_notice: notice }.compact
  rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    PosthogLog.warn("streak_refresh_unavailable")
    redirect_to project_path, flash: { streak_alert: "Couldn't reach Hackatime. Try again in a minute." }
  end
end
