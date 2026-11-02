# Someone's reviewing a ship (in one queue): taken when they open it, kept alive by the page every
# HEARTBEAT, gone once it's been IDLE (or the ship's decided). Anyone else sees it read-only meanwhile; an admin can
# take it over. You hold one at a time in each queue, unless you're an admin.
class ReviewClaim < ApplicationRecord
  IDLE = 30.minutes
  HEARTBEAT = 60.seconds

  belongs_to :ship
  belongs_to :user

  validates :queue, inclusion: { in: ReviewDecision::QUEUES }

  scope :live, -> { where(heartbeat_at: IDLE.ago..) }

  def live? = heartbeat_at >= IDLE.ago

  # Takes the ship for this person: theirs if nobody has it, it's gone idle, it's theirs already, or they're taking
  # over. Returns the claim, whoever it's whose now.
  def self.take(ship, user, queue: "review", takeover: false)
    transaction do
      where(user:, queue:).where.not(ship:).delete_all unless user.admin?
      claim = lock.find_or_create_by!(ship:, queue:) { |new| new.assign_attributes(user:, claimed_at: Time.current, heartbeat_at: Time.current) }
      if claim.user_id == user.id
        claim.update!(heartbeat_at: Time.current)
      elsif !claim.live? || takeover
        claim.update!(user:, claimed_at: Time.current, heartbeat_at: Time.current)
      end
      claim
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Someone else is on it, right now.
  def self.held_by_other?(ship, user, queue: "review")
    live.where(ship:, queue:).where.not(user:).exists?
  end

  # The page says they're still there. False if it isn't theirs any more.
  def self.beat(ship, user, queue: "review")
    where(ship:, user:, queue:).update_all(heartbeat_at: Time.current).positive?
  end

  # Lets the ship go in one queue, or in every queue once it's decided.
  def self.release(ship, queue: nil)
    (queue ? where(ship:, queue:) : where(ship:)).delete_all
  end
end
