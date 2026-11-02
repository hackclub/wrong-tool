# One ship to review (/review/ships/:id): what was submitted, the project's earlier ships, every call made on them,
# and the decision panel. Nobody opens their own ship, unless they're an admin (User#may_review?).
class Review::ShipsController < Review::BaseController
  before_action :set_ship

  def show
    @decision = ReviewDecision.new(ship: @ship, decision: "approved", approved_hours: @ship.hours)
  end

  private
    def set_ship
      @ship = Ship.includes(:decided_by, review_decisions: :reviewer, project: :user).find(params[:ship_id] || params[:id])
      not_found unless current_user.may_review?(@ship)
    end
end
