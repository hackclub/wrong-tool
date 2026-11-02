# The fraud check, from the moment a ship's shipped (Review::FraudVerdictsController): a fraud reviewer scores how much
# they trust it, 1 to 10, with a note for staff. Over PASS_OVER it passes (sus, up to SUS_UP_TO or if they mark it:
# it passes, and staff see the mark), and if a reviewer approved it already it completes (ShipReview.finalize_if_ready).
# At PASS_OVER or under it's rejected, final, whatever a reviewer said, and Clippy tells them with REJECT_NOTE, never
# the score or the note. A fraud pass sends a ship a reviewer sent to fraud back to the review queue.
module FraudCheck
  PASS_OVER = 4
  SUS_UP_TO = 7
  # A reship keeps the last ship's passing check unless this many hours or more were added since (Ship).
  KEEP_UNDER_HOURS = 3
  REJECT_NOTE = "This project can't be accepted in wrong tool. For more information, see https://fraud.hackclub.com"

  def self.passes?(score) = score.to_i > PASS_OVER

  def self.verdict(ship, by:, score:, note:, mark_sus: false)
    score = Integer(score.to_s, exception: false)
    pass = passes?(score)
    made = ReviewDecision.new(ship:, reviewer: by, queue: "fraud", decision: pass ? "fraud_pass" : "fraud_fail", trust_score: score,
                              justification: note, mark_sus: ActiveModel::Type::Boolean.new.cast(mark_sus) || false,
                              note_to_maker: (REJECT_NOTE unless pass))
    finalized = false

    ship.with_lock do
      if (refusal = refusal(ship, by))
        made.errors.add(:base, refusal)
      elsif made.save
        if pass
          ship.update!(fraud_status: made.mark_sus || score <= SUS_UP_TO ? "sus" : "good", fraud_score: score,
                       **(ship.review_hold == "fraud" ? { review_hold: nil, hold_note: nil } : {}))
          ReviewClaim.release(ship, queue: "fraud")
          finalized = ShipReview.finalize_if_ready(ship)
        else
          ship.update!(fraud_status: "fraud", fraud_score: score, status: "rejected", decided_by: by, decided_at: made.created_at,
                       approved_hours: nil, review_hold: nil, hold_note: nil, review_approved_at: nil)
          ReviewClaim.release(ship)
        end
      end
    end

    ReviewNotifier.decided(ship) if made.persisted? && (finalized || !pass)
    made
  end

  def self.refusal(ship, by)
    if !by.fraud_reviewer? || !by.may_review?(ship)
      "You can't check this one."
    elsif !ship.in_review?
      "That one's been decided already."
    elsif !ship.fraud_unchecked?
      "It's been checked already."
    elsif ReviewClaim.held_by_other?(ship, by, queue: "fraud")
      "Someone else is on this one."
    end
  end
  private_class_method :refusal
end
