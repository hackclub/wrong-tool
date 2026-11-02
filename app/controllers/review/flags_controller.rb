# Dismissing one of a ship's flags (ShipFlag#dismiss!), with why: it stays dismissed, and a red flag no longer holds
# up approving it.
class Review::FlagsController < Review::ShipsController
  def update
    flag = @ship.flags.find(params[:id])
    if flag.dismissed? || flag.dismiss!(by: current_user, reason: params[:dismiss_reason])
      redirect_to review_ship_path(@ship, anchor: "review-flags")
    else
      redirect_to review_ship_path(@ship, anchor: "review-flags"), alert: flag.errors.full_messages.to_sentence
    end
  end
end
