# Deciding a ship in the review queue (ShipReview): approved, changes requested, rejected, or sent on to fraud or an
# admin. Once it's made, on to the next ship in line; the page again, with what's missing, if it isn't.
class Review::DecisionsController < Review::ShipsController
  def create
    @decision = ShipReview.decide(@ship, by: current_user, **decision_params.to_h.symbolize_keys)
    if @decision.persisted?
      next_after(@ship, "#{@ship.title}: #{helpers.review_decision_done(@decision)}.")
    else
      @verdict = ReviewDecision.new(ship: @ship, queue: "fraud")
      claim
      show_refusal(@decision)
      render "review/ships/show", status: :unprocessable_entity
    end
  end

  private
    def decision_params
      params.expect(review: %i[decision hold note_to_maker justification approved_hours deflation_reason video_url])
    end
end
