# Spending approved hours (Project#hours_to_spend) on a console, like money: one of each, as many as they cover,
# exactly as set up in the shop (colour, extras: priced into hours by Console#hours_for), from where (the maker's
# store, or a seller an admin approved for it: SellerRequest). It waits until an admin orders it (Admin::OrdersController), and Clippy DMs them then (OrderNotifier).
class Order < ApplicationRecord
  STATUSES = %w[waiting ordered].freeze

  belongs_to :project
  belongs_to :ordered_by, class_name: "User", optional: true

  normalizes :prize_options, with: ->(options) { Console.picks(options) }

  before_validation :price_and_route, on: :create

  validates :status, inclusion: { in: STATUSES }
  validates :prize, inclusion: { in: Console.ids }
  validates :prize, uniqueness: { scope: :project_id, message: "is one you've bought already" }
  validate :as_its_maker_sells_it, :covered_by_approved_hours, on: :create

  scope :waiting, -> { where(status: "waiting") }
  scope :ordered, -> { where(status: "ordered") }

  def waiting? = status == "waiting"
  def ordered? = status == "ordered"

  def console = Console.find(prize)
  def color = console.color(prize_color)

  # "Miyoo Mini Plus in gray, 64GB", as it was bought.
  def configuration
    [ "#{console.full} in #{color.label}", console.extras_label(prize_options) ].compact.join(", ")
  end

  # Where it's ordered from: "Miyoo's store", or the approved seller's site.
  def seller_name
    seller_url == console.url ? console.vendor.name : URI(seller_url).host.to_s.delete_prefix("www.")
  end

  # Why it can't be bought, as Clippy says it.
  def problem
    error = errors.first
    error&.attribute == :prize ? "#{console&.name || "That"} #{error.message}" : error&.message
  end

  # An admin's ordered it: once.
  def ordered!(by:)
    return false unless waiting?

    update!(status: "ordered", ordered_by: by, ordered_at: Time.current)
    OrderNotifier.ordered(self)
    true
  end

  private
    # Its hours, its every option (defaults for any not made), its colour (the first if none), where it comes from
    #, all as they are now.
    def price_and_route
      return unless console && project

      @unknown_options = console.unknown_choices(prize_options)
      self.prize_options = console.choices_for(prize_options)
      self.prize_color = prize_color.presence || console.default_color.id
      self.hours = console.hours_for(prize_options)
      self.seller_url ||= project.seller_requests.find_by(prize:, status: "approved")&.url || console.url
    end

    def as_its_maker_sells_it
      return unless console

      errors.add(:base, "That colour isn't one the #{console.name} comes in.") unless color
      errors.add(:base, "The #{console.name} doesn't come with that.") if @unknown_options.present?
    end

    def covered_by_approved_hours
      return unless project && hours && errors.empty?

      left = project.hours_to_spend
      errors.add(:base, "That's #{hours.to_f.round(1).to_s.delete_suffix(".0")} hours, and you've #{left.round(1).to_s.delete_suffix(".0")} approved to spend.") if hours > left
    end
end
