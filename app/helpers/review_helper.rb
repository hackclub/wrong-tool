# The review pages (Review::QueueController, Review::ShipsController), and anywhere else a ship's status shows to
# staff (the admin projects pages).
module ReviewHelper
  SHIP_STATUS_LABELS = { "in_review" => "In review", "changes_requested" => "Changes requested", "approved" => "Approved",
                         "rejected" => "Rejected" }.freeze
  DECISION_LABELS = { "approved" => "Approved", "changes_requested" => "Asked for changes", "rejected" => "Rejected" }.freeze

  # "Approved", "Changes requested", "Rejected", or "In review".
  def ship_status_label(ship)
    SHIP_STATUS_LABELS.fetch(ship.status)
  end

  # "Approved · Orpheus · Oct 13": the decision, who made it and when; "In review" until then.
  def ship_decision(ship)
    return ship_status_label(ship) if ship.in_review?

    "#{ship_status_label(ship)} · #{reviewer_name(ship.decided_by)} · #{ship.decided_at.strftime("%b %-d")}"
  end

  def review_decision_label(decision)
    DECISION_LABELS.fetch(decision.decision, decision.decision.humanize)
  end

  # Staff see each other by first name; a decision nobody made (from before decisions were kept, or wrong tool's own)
  # is "someone".
  def reviewer_name(user)
    user&.first_name.presence || user&.public_name || "someone"
  end

  # The review pages a reviewer can get between, and the admin home for admins.
  def review_pages
    [ { label: "Queue", path: review_root_path }, ({ label: "Admin", path: admin_root_path } if current_user.admin?) ].compact
  end
end
