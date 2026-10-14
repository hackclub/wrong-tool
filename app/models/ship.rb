# One time someone shipped their project: the title, description, links and screenshot they submitted (kept as they
# were, whatever happens to the project after) and the hours it took. It's in review until an admin approves it or
# sends it back (Admin::ShipsController); sent back, they can ship again.
class Ship < ApplicationRecord
  STATUSES = %w[in_review approved rejected].freeze
  DECISIONS = %w[approved rejected].freeze
  DESCRIPTION_MIN = 40
  URL = %r{\Ahttps?://\S+\z}

  belongs_to :project
  belongs_to :decided_by, class_name: "User", optional: true
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

  scope :in_review, -> { where(status: "in_review") }
  scope :approved, -> { where(status: "approved") }
  scope :decided, -> { where.not(status: "in_review") }
  # Each project's newest ship (of those in the scope so far): the one that stands, whatever came before it.
  scope :latest_per_project, -> { where(id: select("MAX(id)").group(:project_id)) }

  def in_review? = status == "in_review"
  def approved? = status == "approved"
  def rejected? = status == "rejected"

  # An admin's call, made once: false if it's been made already (or isn't a decision). Approving grants the hours it
  # took for the shop to spend (Project#hours_approved), or fewer if the admin says so; never more, never below 0.
  def decide!(decision, by:, hours: nil)
    return false unless in_review? && DECISIONS.include?(decision)

    approved_hours = (hours.presence&.to_d&.clamp(0, self.hours) || self.hours if decision == "approved")
    update!(status: decision, decided_by: by, decided_at: Time.current, approved_hours:)
    true
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
