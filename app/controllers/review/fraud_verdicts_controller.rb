# The fraud check on a ship (FraudCheck): a trust score, a note and maybe a sus mark. Once it's made, on to the next
# in the fraud queue; the page again, with what's missing, if it isn't.
class Review::FraudVerdictsController < Review::ShipsController
  def create
    @verdict = FraudCheck.verdict(@ship, by: current_user, score: verdict_params[:trust_score], note: verdict_params[:justification],
                                         mark_sus: verdict_params[:mark_sus])
    if @verdict.persisted?
      next_after(@ship, "#{@ship.title}: #{helpers.review_decision_done(@verdict)}.")
    else
      @decision = ReviewDecision.new(ship: @ship, decision: "approved", approved_hours: @ship.hours_now)
      claim
      render "review/ships/show", status: :unprocessable_entity
    end
  end

  private
    def set_queue
      @queue = "fraud"
      not_found unless current_user.fraud_reviewer?
    end

    def verdict_params
      params.expect(verdict: %i[trust_score justification mark_sus])
    end
end
