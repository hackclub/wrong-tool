# Hackatime sends you back here once you've let us read your projects and hours. We ask it who you are, keep that
# and the token, and tick off linking Hackatime on your project. Clippy hops, or congratulates you if that was the last
# setup step left.
#
# Hackatime also says what it makes of your hours (its trust level), so that's kept with the rest of it. Nothing about
# it is ever shown to you or changes anything you can do here: it's for whoever reviews your ships (ShipEvidence).
class HackatimeLinksController < ApplicationController
  def create
    return redirect_to onboarding_path unless signed_in?

    token = request.env.dig("omniauth.auth", "credentials", "token").to_s
    identity = Hackatime.identity(token) if token.present?
    return redirect_to project_path, alert: "Couldn't tell who you are on Hackatime. Try again." if identity&.uid.blank?

    was_finished = current_user.project&.setup_finished?
    if current_user.update(hackatime_uid: identity.uid, hackatime_access_token: token,
                           hackatime_trust_level: identity.trust_level, hackatime_trust_checked_at: Time.current)
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "hackatime_linked"
      ) if Rails.configuration.x.posthog_configured

      Hackatime.forget(current_user)
      note_hackatime_projects_you_have
      setup_completed = current_user.project&.setup_finished? && !was_finished
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "project_setup_completed"
      ) if setup_completed && Rails.configuration.x.posthog_configured

      flash[:clippy] = setup_completed ? "congratulate" : "hop"
      redirect_to project_path
    else
      redirect_to project_path, alert: "That Hackatime account #{current_user.errors[:hackatime_uid].first}."
    end
  end

  private
    # The projects you already have on Hackatime, so the first new one can link itself (Project#auto_link_hackatime_project).
    # If Hackatime can't say right now, the project page notes them instead.
    def note_hackatime_projects_you_have
      return unless (project = current_user.project)

      project.available_hackatime_projects = Hackatime.projects(current_user)
      project.auto_link_hackatime_project(project.available_hackatime_projects)
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
    end
end
