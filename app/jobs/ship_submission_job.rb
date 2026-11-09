# Sends decided ships to Airtable for Unified YSWS (ShipSubmission). With a ship, that one, as soon as its decision
# changes. With none, the sweep: every decided ship not sent since it last changed, which catches what Airtable
# wouldn't take before, and every ship decided before this existed.
class ShipSubmissionJob < ApplicationJob
  # Airtable takes 5 requests a second per base.
  PAUSE = 0.25

  retry_on Airtable::Unavailable, wait: :polynomially_longer, attempts: 5

  def perform(ship = nil)
    return ShipSubmission.sync!(ship) if ship
    return unless Airtable.configured?

    ShipSubmission.unsynced.includes(:review_decisions, project: :user).find_each do |unsynced|
      ShipSubmission.sync!(unsynced)
      sleep PAUSE unless Airtable.stubbed
    rescue Airtable::Unavailable => error
      Rails.logger.warn("Ship #{unsynced.id} not sent to Airtable: #{error.message}")
    end
  end
end
