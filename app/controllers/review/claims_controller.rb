# A ship's claim (ReviewClaim): the review page beats every ReviewClaim::HEARTBEAT to keep it (a conflict once it's
# someone else's, so the page shows that), and an admin takes over one someone else is on.
class Review::ClaimsController < Review::ShipsController
  def create
    return not_found unless current_user.admin?

    ReviewClaim.take(@ship, current_user, takeover: true)
    redirect_to review_ship_path(@ship)
  end

  def update
    head(ReviewClaim.beat(@ship, current_user) ? :no_content : :conflict)
  end
end
