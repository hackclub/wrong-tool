# Once, on the deploy that brings Hackatime's real trust level (its admin API): every ship waiting in review or on the
# fraud check gets its evidence gathered again, so reviewers see the trust level without pressing Resync on each.
# It only queues the jobs (ShipEvidenceJob); bin/rails ships:resync does the same by hand.
class ResyncWaitingShipEvidence < ActiveRecord::Migration[8.1]
  def up
    ShipEvidence.request_waiting
  end

  def down
  end
end
