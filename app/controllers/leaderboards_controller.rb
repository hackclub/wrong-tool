# Everyone who's set up, ranked by hours this week (or streak). You're on it too, at the bottom until you're set up.
class LeaderboardsController < ApplicationController
  SORTS = %w[week streak].freeze

  def show
    @project = current_user&.project
    return redirect_to onboarding_path unless @project

    @sort = SORTS.include?(params[:sort]) ? params[:sort] : "week"
  end
end
