# Hack Club Auth sends people back here. Signing in starts a fresh session (and adds you to wrong tool's Slack channels
# the first time); they return to where they came from.
class SessionsController < ApplicationController
  def create
    user = User.from_omniauth(request.env["omniauth.auth"])
    return_to = safe_return_path(request.env["omniauth.origin"])
    reset_session
    session[:user_id] = user.id
    JoinSlackChannelsJob.perform_later(user.id) unless user.slack_channels_joined_at
    user.remember_timezone(cookies[:timezone]) if cookies[:timezone].present?
    SlackTimezoneJob.perform_later(user.id) if user.timezone.blank?

    if Rails.configuration.x.posthog_configured
      PostHog.identify(
        distinct_id: user.posthog_distinct_id,
        properties: user.posthog_properties
      )

      PostHog.capture(
        distinct_id: user.posthog_distinct_id,
        event: "user_signed_up",
        properties: { signup_method: "hack_club_oauth" }
      ) if user.previously_new_record?

      PostHog.capture(
        distinct_id: user.posthog_distinct_id,
        event: "user_logged_in",
        properties: { login_method: "hack_club_oauth" }
      )
    end

    redirect_to return_to || onboarding_path
  end

  def failure
    if params[:strategy] == "hackatime"
      return redirect_to project_path, alert: "Couldn't link Hackatime (#{params[:message].to_s.humanize.downcase}). Try again."
    end

    redirect_to onboarding_path, alert: "Couldn't sign you in with Hack Club (#{params[:message].to_s.humanize.downcase})."
  end

  def destroy
    if current_user && Rails.configuration.x.posthog_configured
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "user_logged_out"
      )
    end

    reset_session
    redirect_to root_path
  end

  private
    # Only paths on this site, so the origin can't send people somewhere else.
    def safe_return_path(origin)
      path = URI.parse(origin.to_s).path.presence
      path if path&.start_with?("/") && !path.start_with?("//")
    rescue URI::InvalidURIError
      nil
    end
end
