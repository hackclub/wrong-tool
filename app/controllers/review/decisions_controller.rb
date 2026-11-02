# Deciding a ship from its review page (ShipReview): approved, changes requested or rejected. Back to the queue once
# it's made; the page again, with what's missing, if it isn't.
class Review::DecisionsController < Review::ShipsController
  def create
    @decision = ShipReview.decide(@ship, by: current_user, **decision_params.to_h.symbolize_keys)
    if @decision.persisted?
      redirect_to review_root_path, notice: "#{@ship.title}: #{helpers.ship_status_label(@ship).downcase}."
    else
      render "review/ships/show", status: :unprocessable_entity
    end
  end

  private
    def decision_params
      params.expect(review: %i[decision note_to_maker justification approved_hours deflation_reason video_url])
    end
end
