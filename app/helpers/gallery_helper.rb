module GalleryHelper
  # Where review's at with a ship, on its card.
  GALLERY_STATUSES = { "in_review" => "In review", "changes_requested" => "Being fixed", "approved" => "Approved",
                       "rejected" => "Not approved" }.freeze

  def gallery_status(ship)
    GALLERY_STATUSES.fetch(ship.status, ship.status.humanize)
  end
end
