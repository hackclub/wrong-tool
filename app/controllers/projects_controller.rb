# Your project: the pledge you signed at the end of onboarding, and setting up to build it.
class ProjectsController < ApplicationController
  before_action :require_project, only: %i[show update]

  # ?step= opens one of the setup steps you can still do (otherwise it's the first one left); ?edit=pace, your pace.
  # ?refresh=1 asks Hackatime for your projects again.
  def show
    @step = params[:step]
    @editing_pace = params[:edit] == "pace"
    @refresh_hackatime = params[:refresh].present?
  end

  # Signing the pledge (the onboarding controller posts it once the ceremony's done). Signing again re-pledges.
  def create
    return head :unauthorized unless signed_in?

    project = current_user.project || current_user.build_project
    if project.update(pledge_params.merge(signed_on: Date.current))
      render json: { location: project_path }, status: :created
    else
      render json: { errors: project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Ticking off a setup step. Clippy hops for each one, and congratulates you when setup's done.
  def update
    was_set_up = @project.set_up?
    @project.available_hackatime_projects = hackatime_projects if setup_params.key?(:link_hackatime_project)
    if @project.update(setup_params)
      flash[:clippy] = @project.set_up? && !was_set_up ? "congratulate" : "hop"
      redirect_to project_path
    else
      @step = "repo" if @project.errors[:repo_url].any?
      @step = "hackatime_project" if @project.errors[:hackatime_projects].any?
      render :show, status: :unprocessable_entity
    end
  end

  private
    def require_project
      @project = current_user&.project
      redirect_to onboarding_path unless @project
    end

    def hackatime_projects
      Hackatime.projects(current_user.slack_id)
    rescue Hackatime::NotFound, Hackatime::Unavailable
      []
    end

    def pledge_params
      params.expect(project: %i[tool tool_name idea prize pace_minutes build_time])
    end

    def setup_params
      params.expect(project: %i[name screenshot tracker link_hackatime_project unlink_hackatime_project slack_joined repo_url
                                repo_later idea_posted idea_skipped pace_minutes party_queued])
    end
end
