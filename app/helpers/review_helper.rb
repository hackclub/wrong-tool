# The review pages (Review::QueueController, Review::ShipsController), and anywhere else a ship's status shows to
# staff (the admin projects pages). `queue` is the page's (Review::BaseController).
module ReviewHelper
  SHIP_STATUS_LABELS = { "in_review" => "In review", "changes_requested" => "Changes requested", "approved" => "Approved",
                         "rejected" => "Rejected" }.freeze
  DECISION_LABELS = { "approved" => "Approved", "changes_requested" => "Asked for changes", "rejected" => "Rejected",
                      "send_fraud" => "Sent to fraud", "send_admin" => "Sent to an admin", "fraud_pass" => "Passed the fraud check",
                      "fraud_fail" => "Failed the fraud check" }.freeze
  FRAUD_LABELS = { "unchecked" => "Not yet", "good" => "Passed", "sus" => "Passed, sus", "fraud" => "Failed" }.freeze

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

  # What just happened, for the notice after a call: "approved", or "approved: it completes once the fraud check
  # passes".
  def review_decision_done(decision)
    ship = decision.ship
    case decision.decision
    when "approved" then ship.approved? ? "approved" : "approved: it completes once the fraud check passes"
    when "fraud_pass" then ship.approved? ? "passed the fraud check, and it's approved" : "passed the fraud check"
    when "fraud_fail" then "failed the fraud check, so it's rejected"
    else review_decision_label(decision).downcase
    end
  end

  def fraud_status_label(ship)
    FRAUD_LABELS.fetch(ship.fraud_status, "Not checked")
  end

  # A ship's page in the queue you're in.
  def review_ship_here(ship, **options)
    review_ship_path(ship, **in_queue, **options)
  end

  # The query that keeps you in the fraud queue (none for the review queue, which is the default).
  def in_queue
    respond_to?(:queue) && queue == "fraud" ? { queue: "fraud" } : {}
  end

  # The calls this person may see on a ship: the fraud check's only to fraud reviewers.
  def visible_decisions(decisions)
    current_user.fraud_reviewer? ? decisions : decisions.reject { |decision| decision.queue == "fraud" }
  end

  # Staff see each other by first name; a decision nobody made (from before decisions were kept, or wrong tool's own)
  # is "someone".
  def reviewer_name(user)
    user&.first_name.presence || user&.public_name || "someone"
  end

  # The review pages a reviewer can get between: the queues they work in, and the admin home for admins.
  def review_pages
    [ ({ label: "Review", path: review_root_path, queue: "review" } if current_user.reviewer?),
      ({ label: "Fraud check", path: review_root_path(queue: "fraud"), queue: "fraud" } if current_user.fraud_reviewer?),
      ({ label: "Admin", path: admin_root_path } if current_user.admin?) ].compact
  end
end
