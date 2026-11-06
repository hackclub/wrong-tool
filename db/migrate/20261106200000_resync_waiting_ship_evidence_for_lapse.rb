# On the deploy that brings Lapse back (Lapse, ShipEvidence.lapse): every ship waiting on a review or the fraud check is
# gathered again, so reviewers see the maker's timelapses without pressing Resync on each. Only if the program key is
# here; without it there's nothing new to gather, and bin/rails ships:resync does it once the key's in.
class ResyncWaitingShipEvidenceForLapse < ActiveRecord::Migration[8.1]
  def up
    ShipEvidence.request_waiting if Lapse.configured?
  end

  def down
  end
end
