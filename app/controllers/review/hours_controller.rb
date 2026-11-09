# An admin changing the hours an approved ship grants (ShipReview.change_hours), with why. Back to the ship either
# way, with what's wrong if it didn't change.
class Review::HoursController < Review::ShipsController
  def update
    change = ShipReview.change_hours(@ship, by: current_user, **params.expect(review: %i[approved_hours justification]).to_h.symbolize_keys)
    if change.persisted?
      redirect_to helpers.review_ship_here(@ship),
                  notice: "#{@ship.title}: #{helpers.project_hours(change.approved_hours)} hrs now."
    else
      redirect_to helpers.review_ship_here(@ship), alert: change.errors.full_messages.to_sentence
    end
  end
end
