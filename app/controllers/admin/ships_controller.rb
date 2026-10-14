# Every ship (Ship), to inspect: in review first, oldest at the top, then decided. Each opens in full, screenshot and
# all, with a button to approve it or send it back. Nobody's told yet either way; that's #wrong's.
class Admin::ShipsController < Admin::BaseController
  def index
    ships = Ship.includes(:decided_by, project: :user)
    @in_review = ships.in_review.order(:created_at)
    @decided = ships.decided.order(decided_at: :desc)
  end

  def show
    @ship = Ship.includes(:decided_by, project: :user).find(params[:id])
    @others = @ship.project.ships.where.not(id: @ship.id).order(created_at: :desc)
  end

  def update
    ship = Ship.find(params[:id])
    decided = ship.decide!(params[:decision].to_s, by: current_user, hours: params[:approved_hours])
    redirect_to admin_ship_path(ship), alert: ("That one's been decided already." unless decided)
  end
end
