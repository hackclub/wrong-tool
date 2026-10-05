# Hackatime sends you back here once you've let us read your projects and hours. We ask it who you are, keep that
# and the token, and tick off linking Hackatime on your project.
class HackatimeLinksController < ApplicationController
  def create
    return redirect_to onboarding_path unless signed_in?

    token = request.env.dig("omniauth.auth", "credentials", "token").to_s
    uid = Hackatime.user_id(token) if token.present?
    return redirect_to project_path, alert: "Couldn't tell who you are on Hackatime. Try again." if uid.blank?

    if current_user.update(hackatime_uid: uid, hackatime_access_token: token)
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "hackatime_linked"
      ) if Rails.configuration.x.posthog_configured

      Hackatime.forget(current_user)
      note_hackatime_projects_you_have
      flash[:clippy] = "hop"
      redirect_to project_path
    else
      redirect_to project_path, alert: "That Hackatime account #{current_user.errors[:hackatime_uid].first}."
    end
  end

  private
    # The projects you already have on Hackatime, so the first new one can link itself (Project#auto_link_hackatime_project).
    # If Hackatime can't say right now, the project page notes them instead.
    def note_hackatime_projects_you_have
      current_user.project&.auto_link_hackatime_project(Hackatime.projects(current_user))
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    end
end
