# A queue (/review, or /review?queue=fraud): every ship waiting in it (ReviewQueue), with who's on it and, for ones
# sent on, the note; then the latest decided, newest first, with who decided them. Coming back here forgets what you
# skipped.
class Review::QueueController < Review::BaseController
  DECIDED_LIMIT = 100

  def show
    session.delete(:"#{queue}_skipped")
    @waiting = ReviewQueue.waiting(queue, current_user).includes(:decided_by, project: :user)
    @claims = ReviewClaim.live.where(queue:, ship: @waiting).includes(:user).index_by(&:ship_id)
    @decided = Ship.includes(:decided_by, project: :user).decided.order(decided_at: :desc).limit(DECIDED_LIMIT)
    @awaiting_fraud = Ship.in_review.where.not(review_approved_at: nil).count
    @decided_today = ReviewDecision.where(reviewer: current_user, queue:, created_at: Time.current.all_day)
                                   .where.not(decision: ReviewDecision::HOLDS + ReviewDecision::EDITS).count
  end
end
