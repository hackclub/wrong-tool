# Asking for a console from another seller than the one the shop orders from (Console#vendor): a link to the same
# console somewhere nearer, so it gets to you without customs. One live ask (waiting or approved) per console for a
# project; an admin approves or denies it (Admin::SellerRequestsController), and Clippy DMs them either way
# (SellerRequestNotifier). Approved, that's where the console's ordered from if it's their pick.
class SellerRequest < ApplicationRecord
  STATUSES = %w[pending approved denied].freeze
  DECISIONS = %w[approved denied].freeze
  LIVE = %w[pending approved].freeze
  URL_MAX = 2000

  belongs_to :project
  belongs_to :decided_by, class_name: "User", optional: true

  normalizes :url, with: ->(url) { url.strip }

  validates :status, inclusion: { in: STATUSES }
  validates :prize, inclusion: { in: Console.ids }
  validates :url, format: { with: %r{\Ahttps?://[^\s/]+\.[^\s/]+(/\S*)?\z}, message: "isn't a link to a listing" },
                  length: { maximum: URL_MAX }
  validate :not_the_shops_seller, :one_live_ask_per_console, on: :create

  scope :pending, -> { where(status: "pending") }
  scope :decided, -> { where.not(status: "pending") }
  scope :live, -> { where(status: LIVE) }

  def pending? = status == "pending"
  def approved? = status == "approved"
  def denied? = status == "denied"

  def console = Console.find(prize)

  # "aliexpress.com", for a sentence.
  def host = URI(url).host.to_s.delete_prefix("www.")

  # An admin's call, made once: false if it's been made already (or isn't a decision).
  def decide!(decision, by:)
    return false unless pending? && DECISIONS.include?(decision)

    update!(status: decision, decided_by: by, decided_at: Time.current)
    SellerRequestNotifier.decided(self)
    true
  end

  # Why it can't be sent, as Clippy says it: "that isn't a link to a listing".
  def problem
    error = errors.first
    error&.attribute == :url ? "that #{error.message}" : error&.full_message
  end

  private
    def not_the_shops_seller
      return unless console && errors[:url].empty? && host == console.site.delete_prefix("www.")

      errors.add(:url, "is #{console.vendor.name}, where it comes from already")
    end

    def one_live_ask_per_console
      return unless project && SellerRequest.live.exists?(project:, prize:)

      errors.add(:base, "There's a link in for the #{console&.name} already")
    end
end
