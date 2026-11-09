# Deciding a ship in the review queue (Review::DecisionsController): approve it (the hours it grants for the shop, or
# fewer with a reason, and what was checked), ask for changes, reject it for good, or send it on, to fraud or an
# admin, with a note for them. Each call is a ReviewDecision, made with the ship locked so two reviewers can't both
# decide it, not while someone else is on it (ReviewClaim), and no approving with a red flag nobody's dismissed
# (ShipFlag).
#
# A ship completes once it's approved and has passed the fraud check (FraudCheck), whichever comes second
# (finalize_if_ready): only then are the hours theirs, and Clippy tells them (ReviewNotifier). Until then it's in
# review, to them. Asking for changes or rejecting tells them at once.
module ShipReview
  # Where a reviewer can send a ship instead of deciding it, as the decision it makes.
  SENDS = { "fraud" => "send_fraud", "admin" => "send_admin" }.freeze

  # The decision, saved, or with what's wrong with it (in errors). A ship that's been decided already, or that this
  # person can't decide now, gets an error and stays as it was. `hold` is where "hold" sends it (fraud or admin).
  def self.decide(ship, by:, decision:, hold: nil, note_to_maker: nil, justification: nil, approved_hours: nil, deflation_reason: nil,
                  video_url: nil)
    decision = SENDS.fetch(hold.to_s, "hold") if decision == "hold"
    approving = decision == "approved"
    made = ReviewDecision.new(ship:, reviewer: by, queue: "review", decision:, justification:, video_url:,
                              note_to_maker: (note_to_maker unless ReviewDecision::HOLDS.include?(decision)),
                              approved_hours: (approved_hours.presence if approving), deflation_reason: (deflation_reason if approving))
    finalized = false

    ship.with_lock do
      if (refusal = refusal(ship, by, made))
        made.errors.add(:base, refusal)
      elsif made.save
        apply(ship, made)
        finalized = finalize_if_ready(ship) if made.approved?
      end
    end

    ReviewNotifier.decided(ship) if made.persisted? && (finalized || made.changes_requested? || made.rejected?)
    made
  end

  # Approved and passed the fraud check: it's done. The hours are the approval's, and so is who decided it. Called with
  # the ship locked, by whichever came second; true if it completed just now (so the caller tells them).
  def self.finalize_if_ready(ship)
    return false unless ship.awaiting_fraud? && ship.fraud_passed?

    approval = ship.review_decisions.reload.select(&:approved?).last
    ship.record_call!(status: "approved", approved_hours: granted_hours(ship), decided_by: approval.reviewer, decided_at: Time.current,
                 review_hold: nil, hold_note: nil)
    ReviewClaim.release(ship)
    true
  end

  # An admin changing the hours an approved ship grants (or will, once the fraud check passes), with why: kept as a
  # decision of its own (hours_changed). Up to the hours it took, and not below what the maker's spent in the shop
  # already. The maker isn't told.
  def self.change_hours(ship, by:, approved_hours:, justification:)
    made = ReviewDecision.new(ship:, reviewer: by, queue: "review", decision: "hours_changed", approved_hours: approved_hours.presence,
                              justification:)

    ship.with_lock do
      if (refusal = hours_refusal(ship, by, made))
        made.errors.add(:base, refusal)
      elsif made.save
        ship.record_call!(approved_hours: made.approved_hours) if ship.approved?
      end
    end
    made
  end

  # What an approved ship grants: the latest approval's hours, or an admin's change since.
  def self.granted_hours(ship)
    ship.review_decisions.select { |decision| decision.approved? || decision.hours_changed? }.last&.approved_hours
  end

  # Why this person can't make this call on this ship right now, or nil.
  def self.refusal(ship, by, made)
    if !ReviewDecision::VERDICTS.include?(made.decision) && !made.hold?
      "Pick approve, request changes, reject, or send it on to fraud or an admin."
    elsif !by.reviewer? || !by.may_review?(ship)
      "You can't decide this one."
    elsif !ship.in_review?
      "That one's been decided already."
    elsif ship.awaiting_fraud?
      "It's approved already, and waiting on the fraud check."
    elsif ship.review_hold == "admin" && !by.admin?
      "It's been sent to an admin, so it's theirs to decide."
    elsif ship.review_hold == "fraud" && !by.admin?
      "It's been sent to fraud: it's back in the queue once the fraud check passes."
    elsif made.decision == "send_fraud" && !ship.fraud_unchecked?
      "The fraud check's done already."
    elsif ReviewClaim.held_by_other?(ship, by)
      "Someone else is on this one."
    elsif made.approved? && (red = ship.flags.open.danger.pluck(:title)).any?
      "Dismiss the red flags first, with why: #{red.to_sentence}"
    end
  end

  def self.hours_refusal(ship, by, made)
    if !by.admin?
      "Only an admin can change the hours."
    elsif !ship.approved? && !ship.awaiting_fraud?
      "Only an approved ship's hours can change."
    elsif made.approved_hours && made.approved_hours == granted_hours(ship)
      "That's the hours it has already."
    elsif ship.approved? && made.approved_hours && (spent = ship.project.hours_spent) > approved_after(ship, made.approved_hours)
      "They've spent #{spent.round(2).to_s.delete_suffix(".0")} hours in the shop already, so it can't go below that."
    end
  end

  # The project's approved hours with this ship's at these.
  def self.approved_after(ship, hours)
    others = ship.project.ships.approved.where.not(id: ship.id).map { |other| other.approved_hours || other.hours }
    [ *others, hours ].max.to_f
  end

  def self.apply(ship, decision)
    case decision.decision
    when "approved"
      ship.record_call!(review_approved_at: decision.created_at, review_hold: nil, hold_note: nil)
    when "send_fraud", "send_admin"
      ship.record_call!(review_hold: SENDS.key(decision.decision), hold_note: decision.justification)
      ReviewClaim.release(ship, queue: "review")
    else
      ship.record_call!(status: decision.decision, decided_by: decision.reviewer, decided_at: decision.created_at, approved_hours: nil,
                   review_hold: nil, hold_note: nil, review_approved_at: nil)
      ReviewClaim.release(ship)
    end
  end
  private_class_method :refusal, :hours_refusal, :approved_after, :apply
end
