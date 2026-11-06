# Once more, on the deploy that gathers Hackatime's trust level on its own (ShipEvidence.trust): the waiting ships whose
# maker's token had stopped working got no trust level from the last resync, so every waiting ship is gathered again.
class ResyncWaitingShipEvidenceForTrust < ActiveRecord::Migration[8.1]
  def up
    ShipEvidence.request_waiting
  end

  def down
  end
end
