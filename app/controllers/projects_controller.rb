# Your project: the pledge you signed at the end of onboarding, and setting up to build it.
class ProjectsController < ApplicationController
  before_action :require_project, only: %i[show update hours]

  # ?step= opens one of the setup steps you can still do (otherwise it's the first one left); ?edit=pace, your pace.
  # ?refresh=1 asks Hackatime for your projects again.
  def show
    @step = params[:step]
    @editing_pace = params[:edit] == "pace"
    @refresh_hackatime = params[:refresh].present?
    flash.now[:clippy] = "hop" if auto_link_hackatime_project(refresh: @refresh_hackatime)
    @refresh_hackatime = false if @project.available_hackatime_projects # just asked: the projects step can use that
    current_user.sync_streak_if_stale!
  end

  # Your hours from Hackatime, for the pomodoro to keep up to date (and, before you've linked a Hackatime project,
  # for your project page to notice when one links itself); ?refresh=1 asks Hackatime now.
  def hours
    flash[:clippy] = "hop" if auto_link_hackatime_project(refresh: params[:refresh].present?)
    hours = @project.hours_logged(refresh: params[:refresh].present?)
    render json: { hours:, label: helpers.project_hours_label(@project, hours), tracking: @project.tracking?,
                   checked_at: Time.current.iso8601 }
  end

  # Signing the pledge (the onboarding controller posts it once the ceremony's done). Signing again re-pledges, like
  # changing your tool from your project page: everything you chose is replaced, but you keep the day you first signed,
  # so your schedule doesn't move.
  def create
    return head :unauthorized unless signed_in?

    project = current_user.project || current_user.build_project
    repledged = project.persisted?
    if project.update(pledge_params.merge(signed_on: project.signed_on || Date.current))
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "project_pledged",
        properties: { repledged: }
      ) if Rails.configuration.x.posthog_configured

      render json: { location: accept_pending_buddy_invite(project) ? buddy_path : project_path }, status: :created
    else
      render json: { errors: project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Ticking off a setup step, or changing your project. Clippy hops for each one, and congratulates you when you're
  # through setup.
  def update
    if setup_params.key?(:hackatime_project_names) || (@project.hackatime_linked? && @project.hackatime_projects.none?)
      @project.available_hackatime_projects = hackatime_projects
    end
    was_finished = @project.setup_finished?
    if @project.update(setup_params)
      setup_completed = @project.setup_finished? && !was_finished
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "project_setup_completed"
      ) if setup_completed && Rails.configuration.x.posthog_configured

      flash[:clippy] = setup_completed ? "congratulate" : "hop"
      redirect_to project_path
    else
      @step = "repo" if @project.errors[:repo_url].any?
      @step = "hackatime_project" if @project.errors[:hackatime_projects].any?
      render :show, status: :unprocessable_entity
    end
  end

  private
    # Someone followed a buddy invite before they had a project (BuddyInvitesController): now they do, pair them.
    def accept_pending_buddy_invite(project)
      code = session.delete(:buddy_code)
      inviter = Project.find_by(buddy_code: code) if code
      inviter && project.pair_with(inviter).persisted?
    end

    def require_project
      @project = current_user&.project
      redirect_to onboarding_path unless @project
    end

    # What's on Hackatime for you to pick from, or nil if it can't say right now.
    def hackatime_projects(refresh: false)
      Hackatime.projects(current_user, refresh:)
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end

    # Before you've picked a Hackatime project, links the first new one you log time on (Project#auto_link_hackatime_project).
    # Notes what Hackatime has for you to pick from too (left unknown if it can't say right now). Returns the name it
    # linked, if it did.
    def auto_link_hackatime_project(refresh: false)
      return unless @project.hackatime_linked? && @project.hackatime_projects.none?

      @project.available_hackatime_projects = Hackatime.projects(current_user, refresh:)
      name = @project.auto_link_hackatime_project(@project.available_hackatime_projects)
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "hackatime_project_auto_linked"
      ) if name && Rails.configuration.x.posthog_configured
      name
    rescue Hackatime::NotLinked, Hackatime::Expired, Hackatime::Unavailable
      nil
    end

    def pledge_params
      params.expect(project: %i[tool tool_name idea prize pace_minutes build_time])
    end

    def setup_params
      params.expect(project: [ :name, :screenshot, :repo_url, :repo_later, :pace_minutes, :party_queued, :buddy_invited,
                               :buddy_skipped, :hackatime_auto_linked, hackatime_project_names: [] ])
    end
end
