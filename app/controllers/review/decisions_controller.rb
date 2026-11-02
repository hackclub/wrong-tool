# Deciding a ship from its review page (ShipReview): approved, changes requested or rejected. Once it's made, on to
# the next ship in line (ReviewQueue), or the queue if that's all; the page again, with what's missing, if it isn't.
class Review::DecisionsController < Review::ShipsController
  def create
    @decision = ShipReview.decide(@ship, by: current_user, **decision_params.to_h.symbolize_keys)
    if @decision.persisted?
      done = "#{@ship.title}: #{helpers.ship_status_label(@ship).downcase}."
      if (upcoming = ReviewQueue.next_for(current_user, after: @ship, skip: skipped))
        redirect_to review_ship_path(upcoming), notice: "#{done} Next up."
      else
        redirect_to review_root_path, notice: "#{done} That's the whole queue."
      end
    else
      claim
      render "review/ships/show", status: :unprocessable_entity
    end
  end

  private
    def decision_params
      params.expect(review: %i[decision note_to_maker justification approved_hours deflation_reason video_url])
    end
end
