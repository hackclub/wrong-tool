# One ship (/review/ships/:id, ?queue=fraud for the fraud check): what was submitted and what we found, the
# project's earlier ships, every call made on them, and the panel for this queue: the decision, or the trust score.
# Nobody opens their own ship, unless they're an admin (User#may_review?). Opening one that's waiting in this queue
# claims it (ReviewClaim), unless someone else is on it.
class Review::ShipsController < Review::BaseController
  before_action :set_ship
  # Ships from before evidence was gathered get theirs the first time they're opened.
  before_action(only: :show) { ShipEvidence.request(@ship) unless @ship.evidence }

  def show
    @decision = ReviewDecision.new(ship: @ship, decision: "approved", approved_hours: @ship.hours_now)
    @verdict = ReviewDecision.new(ship: @ship, queue: "fraud")
    claim
  end

  private
    def claim
      @claim = ReviewClaim.take(@ship, current_user, queue:) if claimable?
    end

    # Waiting on this person, in this queue.
    def claimable?
      return false unless @ship.in_review?

      if queue == "fraud"
        @ship.fraud_unchecked?
      else
        current_user.reviewer? && !@ship.awaiting_fraud? && (@ship.review_hold.nil? || current_user.admin?)
      end
    end

    def set_ship
      @ship = Ship.includes(:decided_by, :evidence, review_decisions: :reviewer, flags: :dismissed_by, project: :user)
                  .find(params[:ship_id] || params[:id])
      not_found unless current_user.may_review?(@ship)
    end

    # On to the next in this queue after this ship, with what was just done; or back to the queue if that's all.
    def next_after(ship, done)
      if (upcoming = ReviewQueue.next_for(current_user, queue:, after: ship, skip: skipped))
        redirect_to review_ship_path(upcoming, queue: (queue if queue == "fraud")), notice: "#{done} Next up."
      else
        redirect_to review_root_path(queue: (queue if queue == "fraud")), notice: "#{done} That's the whole queue."
      end
    end
end
