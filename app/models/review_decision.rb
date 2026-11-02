# One call on a ship, kept for good (ShipReview makes them): approved (with the hours it grants and why), changes
# requested (they can ship again) or rejected (final), each with a note to the maker and a staff-only justification.
# The ship's history is its decisions, newest last.
class ReviewDecision < ApplicationRecord
  QUEUES = %w[review fraud].freeze
  VERDICTS = %w[approved changes_requested rejected].freeze
  DECISIONS = VERDICTS
  # What a reviewer writes, at the least: what they checked, for an approval (staff only); what to change or why
  # not, to the maker; and why some hours don't count, when they don't.
  JUSTIFICATION_MIN = 30
  NOTE_MIN = 10
  DEFLATION_REASON_MIN = 10
  URL = %r{\Ahttps?://\S+\z}

  belongs_to :ship
  belongs_to :reviewer, class_name: "User", optional: true

  normalizes :note_to_maker, :justification, :deflation_reason, :video_url, with: ->(text) { text.strip.presence }

  validates :queue, inclusion: { in: QUEUES }
  validates :decision, inclusion: { in: DECISIONS }
  with_options if: :approved? do
    validates :justification, length: { minimum: JUSTIFICATION_MIN, too_short: "needs at least %{count} characters: what you checked, and what's in it" }
    validates :approved_hours, numericality: { greater_than_or_equal_to: 0, message: "should be a number of hours" }
    validate :approved_hours_within_ship
    validate :deflation_explained
  end
  validates :note_to_maker, length: { minimum: NOTE_MIN, too_short: "needs at least %{count} characters: they'll read it" },
                            if: -> { changes_requested? || rejected? }
  validates :video_url, format: { with: URL, message: "should be a link" }, allow_nil: true

  scope :verdicts, -> { where(decision: VERDICTS) }

  def approved? = decision == "approved"
  def changes_requested? = decision == "changes_requested"
  def rejected? = decision == "rejected"

  # Fewer hours than the ship took.
  def deflated?
    approved? && approved_hours.present? && approved_hours < ship.hours
  end

  private
    def approved_hours_within_ship
      errors.add(:approved_hours, "can't be more than the #{ship.hours.to_f.round(2)} it took") if approved_hours && approved_hours > ship.hours
    end

    def deflation_explained
      return unless deflated? && deflation_reason.to_s.length < DEFLATION_REASON_MIN

      errors.add(:deflation_reason, "needs at least #{DEFLATION_REASON_MIN} characters: why some hours don't count")
    end
end
