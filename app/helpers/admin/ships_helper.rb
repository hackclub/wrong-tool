# The admin ships pages (Admin::ShipsController).
module Admin::ShipsHelper
  SHIP_STATUS_LABELS = { "in_review" => "In review", "approved" => "Approved", "rejected" => "Sent back" }.freeze

  # "Approved", "Sent back", or "In review".
  def ship_status_label(ship)
    SHIP_STATUS_LABELS.fetch(ship.status)
  end

  # "Approved · Orpheus · Oct 13": the decision, who made it and when; "In review" until then.
  def ship_decision(ship)
    return ship_status_label(ship) if ship.in_review?

    "#{ship_status_label(ship)} · #{ship.decided_by&.first_name.presence || "someone"} · #{ship.decided_at.strftime("%b %-d")}"
  end
end
