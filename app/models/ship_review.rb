# Deciding a ship in review (Review::ShipsController): approve it (the hours it grants for the shop, or fewer with a
# reason, and what was checked), ask for changes, or reject it for good. Each call is a ReviewDecision, made once,
# with the ship locked so two reviewers can't both decide it, then Clippy DMs the maker (ReviewNotifier).
module ShipReview
  # The decision, saved, or with what's wrong with it (in errors). A ship that's been decided already, or that this
  # person can't decide, gets an error and stays as it was.
  def self.decide(ship, by:, decision:, note_to_maker: nil, justification: nil, approved_hours: nil, deflation_reason: nil,
                  video_url: nil)
    made = ReviewDecision.new(ship:, reviewer: by, queue: "review", decision:, note_to_maker:, justification:,
                              video_url:, approved_hours: (approved_hours.presence if decision == "approved"),
                              deflation_reason: (deflation_reason if decision == "approved"))

    ship.with_lock do
      if !ReviewDecision::VERDICTS.include?(decision)
        made.errors.add(:decision, "should be approve, request changes or reject")
      elsif !by.reviewer? || !by.may_review?(ship)
        made.errors.add(:base, "You can't decide this one.")
      elsif !ship.in_review?
        made.errors.add(:base, "That one's been decided already.")
      elsif made.save
        apply(ship, made)
      end
    end

    ReviewNotifier.decided(ship) if made.persisted?
    made
  end

  def self.apply(ship, decision)
    ship.update!(status: decision.decision, decided_by: decision.reviewer, decided_at: decision.created_at,
                 approved_hours: (decision.approved_hours if decision.approved?))
  end
  private_class_method :apply
end
