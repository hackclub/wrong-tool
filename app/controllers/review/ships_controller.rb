# One ship to review (/review/ships/:id): what was submitted, the project's earlier ships, every call made on them,
# and the decision panel. Nobody opens their own ship, unless they're an admin (User#may_review?). A reviewer opening
# one in review claims it (ReviewClaim), unless someone else is on it.
class Review::ShipsController < Review::BaseController
  before_action :set_ship

  def show
    @decision = ReviewDecision.new(ship: @ship, decision: "approved", approved_hours: @ship.hours)
    claim
  end

  # Ships from before evidence was gathered get theirs the first time they're opened.
  before_action only: :show do
    ShipEvidence.request(@ship) unless @ship.evidence
  end

  private
    def claim
      @claim = ReviewClaim.take(@ship, current_user) if @ship.in_review? && current_user.reviewer?
    end

    # What you skipped since you were last at the queue: next and skip pass over them.
    def skipped
      session[:review_skipped].to_a
    end

    def set_ship
      @ship = Ship.includes(:decided_by, :evidence, review_decisions: :reviewer, flags: :dismissed_by, project: :user)
                  .find(params[:ship_id] || params[:id])
      not_found unless current_user.may_review?(@ship)
    end
end
