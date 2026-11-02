# The review queue (/review): every ship waiting on a reviewer, oldest first, since every ship (a reship after changes
# too) joins at the back; then the latest decided, newest first, with who decided them.
class Review::QueueController < Review::BaseController
  DECIDED_LIMIT = 100

  def show
    ships = Ship.includes(:decided_by, project: :user)
    @waiting = ships.in_review.order(:created_at, :id)
    @decided = ships.decided.order(decided_at: :desc).limit(DECIDED_LIMIT)
    @decided_today = ReviewDecision.verdicts.where(reviewer: current_user, created_at: Time.current.all_day).count
  end
end
