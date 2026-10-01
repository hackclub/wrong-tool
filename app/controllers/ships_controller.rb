# Shipping your project: the form, and once it's submitted, that it's in review. Opens once you're set up.
class ShipsController < ApplicationController
  before_action :require_set_up_project

  def show
    @ship = @project.ship_in_review || @project.ships.build(title: @project.title, repo_url: @project.repo_url)
  end

  def create
    return redirect_to project_ship_path if @project.ship_in_review

    @ship = @project.ship!(ship_params)
    if @ship.persisted?
      flash[:clippy] = "congratulate"
      redirect_to project_ship_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def require_set_up_project
      @project = current_user&.project
      return redirect_to onboarding_path unless @project

      redirect_to project_path unless @project.set_up?
    end

    def ship_params
      params.expect(ship: %i[title description repo_url demo_url screenshot screenshot_shows_game])
    end
end
