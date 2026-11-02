# One time someone shipped their project: the title, description, links and screenshot they submitted (kept as they
# were, whatever happens to the project after) and the hours it took. It's in review until a reviewer approves it,
# asks for changes or rejects it (ShipReview, from Review::ShipsController). Asked for changes, they can ship again
# for CHANGES_DAYS, deadline or not; rejected is final. Every call is kept (review_decisions).
class Ship < ApplicationRecord
  STATUSES = %w[in_review changes_requested approved rejected].freeze
  # How long you have to ship again with the changes asked for, from the day they're asked.
  CHANGES_DAYS = 7
  DESCRIPTION_MIN = 40
  URL = %r{\Ahttps?://\S+\z}

  belongs_to :project
  belongs_to :decided_by, class_name: "User", optional: true
  has_many :review_decisions, -> { order(:created_at, :id) }, dependent: :destroy, inverse_of: :ship
  has_many :review_claims, dependent: :delete_all
  # What its reviewer sees about it besides what was submitted, gathered once it's shipped, and what's odd about it.
  has_one :evidence, class_name: "ShipEvidence", dependent: :destroy
  has_many :flags, class_name: "ShipFlag", dependent: :destroy
  has_one_attached :screenshot

  # The checkbox under the screenshot: it shows the game running inside the tool, not a mockup.
  attribute :screenshot_shows_game, :boolean, default: false

  normalizes :title, :description, with: ->(value) { value.strip }
  normalizes :repo_url, :demo_url, with: ->(url) { url.strip.then { |stripped| stripped.match?(%r{\A[a-z][a-z0-9+.-]*://}i) || stripped.blank? ? stripped : "https://#{stripped}" } }

  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true, length: { maximum: 80 }
  validates :description, length: { minimum: DESCRIPTION_MIN, too_short: "needs at least %{count} characters" }
  validates :repo_url, :demo_url, format: { with: URL, message: "should be a link" }
  validates :screenshot, presence: { message: "is needed" }
  validate :screenshot_is_an_image
  validates :screenshot_shows_game, acceptance: { message: "has to show the game running, not a mockup", accept: true },
                                    on: :create

  after_create_commit { ShipEvidence.request(self) }

  scope :in_review, -> { where(status: "in_review") }
  scope :approved, -> { where(status: "approved") }
  scope :decided, -> { where.not(status: "in_review") }
  # Each project's newest ship (of those in the scope so far): the one that stands, whatever came before it.
  scope :latest_per_project, -> { where(id: select("MAX(id)").group(:project_id)) }

  def in_review? = status == "in_review"
  def changes_requested? = status == "changes_requested"
  def approved? = status == "approved"
  def rejected? = status == "rejected"

  # The call that decided it (the latest verdict), for its note to the maker.
  def verdict
    review_decisions.select { |decision| ReviewDecision::VERDICTS.include?(decision.decision) }.last
  end

  # Asked for changes, the end of the CHANGES_DAYS-th day after, where they are.
  def changes_due_at
    return unless changes_requested? && decided_at

    zone = project.user.time_zone
    (decided_at.in_time_zone(zone).to_date + CHANGES_DAYS).in_time_zone(zone).end_of_day
  end

  # Asked for changes and still in time to ship them.
  def reshippable?(now: Time.current)
    changes_requested? && changes_due_at.present? && now <= changes_due_at
  end

  private
    def screenshot_is_an_image
      return unless screenshot.attached?

      if !Project::SCREENSHOT_TYPES.include?(screenshot.blob.content_type)
        errors.add(:screenshot, "should be a PNG, JPEG, WebP or GIF")
      elsif screenshot.blob.byte_size > Project::SCREENSHOT_MAX_SIZE
        errors.add(:screenshot, "should be under 5 MB")
      end
    end
end
