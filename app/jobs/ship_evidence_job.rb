# Gathers a ship's evidence for its reviewer (ShipEvidence.build!): once it's shipped, and again on Resync. A source
# that can't be reached is noted in the evidence (and flagged), not retried: Resync asks again.
class ShipEvidenceJob < ApplicationJob
  def perform(ship)
    ShipEvidence.build!(ship)
  end
end
