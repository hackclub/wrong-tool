# One time someone shipped their project: the title, description, links and screenshot they submitted (kept as they
# were, whatever happens to the project after) and the hours it took. It's in review until a reviewer approves it,
# asks for changes or rejects it (ShipReview, from Review::ShipsController). Asked for changes, they can ship again
# for CHANGES_DAYS, deadline or not; rejected is final. Every call is kept (review_decisions).
class Ship < ApplicationRecord
  STATUSES = %w[in_review changes_requested approved rejected].freeze
  # The fraud check (FraudCheck): unchecked until a fraud reviewer scores it, then passed (good, or sus: it passes, and
  # staff see the mark) or fraud (rejected, final). Ships decided before the check have none.
  FRAUD_STATUSES = %w[unchecked good sus fraud].freeze
  # Sent on by a reviewer (ShipReview.decide): to fraud, out of the review queue until the fraud check passes, or to an
  # admin, out of it for everyone else.
  HOLDS = %w[fraud admin].freeze
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
  # What the maker submitted is checked when they submit or edit it, not when a reviewer's call is saved
  # (#record_call!): ships from before a rule existed can still be decided.
  with_options on: %i[create update] do
    validates :description, length: { minimum: DESCRIPTION_MIN, too_short: "needs at least %{count} characters" }
    validates :repo_url, :demo_url, format: { with: URL, message: "should be a link" }
    validates :screenshot, presence: { message: "is needed" }
    validate :screenshot_is_an_image
  end
  validates :screenshot_shows_game, acceptance: { message: "has to show the game running, not a mockup", accept: true },
                                    on: :create

  validates :fraud_status, inclusion: { in: FRAUD_STATUSES }, allow_nil: true
  validates :review_hold, inclusion: { in: HOLDS }, allow_nil: true

  before_create :start_fraud_check
  after_create :note_fraud_check_kept, if: -> { @fraud_check_from }
  after_create_commit { ShipEvidence.request(self) }
  # Decided, or its decision or hours changed since: to Airtable for Unified YSWS (ShipSubmission).
  after_update_commit -> { ShipSubmissionJob.perform_later(self) },
                      if: -> { ShipSubmission.sendable?(self) && (saved_change_to_status? || saved_change_to_approved_hours?) }

  scope :in_review, -> { where(status: "in_review") }
  scope :approved, -> { where(status: "approved") }
  scope :decided, -> { where.not(status: "in_review") }
  # Each project's newest ship (of those in the scope so far): the one that stands, whatever came before it.
  scope :latest_per_project, -> { where(id: select("MAX(id)").group(:project_id)) }

  def in_review? = status == "in_review"
  def changes_requested? = status == "changes_requested"
  def approved? = status == "approved"
  def rejected? = status == "rejected"

  # The call that decided it (the latest verdict, or failing the fraud check), for its note to the maker.
  def verdict
    review_decisions.select { |decision| ReviewDecision::FINAL.include?(decision.decision) }.last
  end

  def fraud_unchecked? = fraud_status == "unchecked"
  def fraud_passed? = %w[good sus].include?(fraud_status)

  # A reviewer approved it, and it's waiting on the fraud check to complete.
  def awaiting_fraud?
    in_review? && review_approved_at.present?
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

  # What it can be approved for: the project's hours now, as of the last Hackatime sync, since they kept working while
  # it waited; never less than it took when shipped.
  def hours_now
    [ hours.to_f, project.hours_logged.to_f ].max
  end

  # Saves a reviewer's or the fraud check's call. Status and holds are still checked; what the maker submitted isn't.
  def record_call!(attributes)
    assign_attributes(attributes)
    save!(context: :review)
  end

  private
    # A ship starts the fraud check, unless the project's last passed one, with fewer than
    # FraudCheck::KEEP_UNDER_HOURS added since: then it keeps that one's.
    def start_fraud_check
      self.fraud_status = "unchecked"
      last = project.ships.where(fraud_status: %w[good sus]).order(:created_at, :id).last
      return unless last && hours - last.hours < FraudCheck::KEEP_UNDER_HOURS

      self.fraud_status, self.fraud_score = last.fraud_status, last.fraud_score
      @fraud_check_from = last
    end

    def note_fraud_check_kept
      review_decisions.create!(queue: "fraud", decision: "fraud_pass", trust_score: fraud_score, mark_sus: fraud_status == "sus",
                               justification: "Kept from the ship before (#{@fraud_check_from.hours.to_f.round(1)} hrs): under " \
                                              "#{FraudCheck::KEEP_UNDER_HOURS} hrs added since.")
    end

    def screenshot_is_an_image
      return unless screenshot.attached?

      if !Project::SCREENSHOT_TYPES.include?(screenshot.blob.content_type)
        errors.add(:screenshot, "should be a PNG, JPEG, WebP or GIF")
      elsif screenshot.blob.byte_size > Project::SCREENSHOT_MAX_SIZE
        errors.add(:screenshot, "should be under 5 MB")
      end
    end
end
