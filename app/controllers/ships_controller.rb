# Shipping your project: the form, and once it's submitted, that it's in review. Opens once you're set up and your
# hours come from a Hackatime project, and closes after your deadline, with a couple of quiet days' grace
# (Project#ship_cutoff). Asked for changes, it opens again with what to change and what you shipped last; rejected,
# it says why, and never opens again.
class ShipsController < ApplicationController
  before_action :require_set_up_project

  def show
    @ship = @project.ship_in_review || new_ship
    @closed = !@ship.persisted? && !@project.may_ship?
  end

  def create
    return redirect_to project_ship_path if @project.ship_in_review || !@project.may_ship? || current_user.needs_address?

    @ship = @project.ship!(ship_params)
    if @ship.persisted?
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "project_shipped"
      ) if Rails.configuration.x.posthog_configured
      PosthogLog.info("project_shipped")

      flash[:clippy] = "congratulate"
      redirect_to project_ship_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    # Asked for changes, it starts from what you shipped then.
    def new_ship
      last = @project.latest_ship
      last = nil unless last&.changes_requested?
      @project.ships.build(title: @project.title, repo_url: @project.repo_url, description: last&.description, demo_url: last&.demo_url)
    end

    def require_set_up_project
      @project = current_user&.project
      return redirect_to onboarding_path unless @project

      redirect_to project_path unless @project.set_up? && @project.tracking?
    end

    def ship_params
      params.expect(ship: %i[title description repo_url demo_url screenshot screenshot_shows_game])
    end
end
