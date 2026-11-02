# Resync on a review page: gather the ship's evidence again (ShipEvidence.request), say, after they fixed the repo.
class Review::EvidencesController < Review::ShipsController
  def create
    ShipEvidence.request(@ship)
    redirect_to review_ship_path(@ship), notice: "Gathering it again. Reload in a minute."
  end
end
