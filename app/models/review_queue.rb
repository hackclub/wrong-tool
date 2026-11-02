# The review queue's order, and what's next: ships in review, oldest first (a reship joins at the back, since it's a
# new ship), less the ones someone else is on and your own. Next comes after the one you were on, wrapping round to
# the front; ones you skipped stay out of it until you're back at the queue.
module ReviewQueue
  def self.waiting
    Ship.in_review.order(:created_at, :id)
  end

  def self.open_to(user, skip: [])
    ships = waiting.where.not(id: ReviewClaim.live.where(queue: "review").where.not(user:).select(:ship_id))
                   .where.not(id: skip)
    user.admin? ? ships : ships.joins(:project).where.not(projects: { user_id: user.id })
  end

  # The next ship for this person, after the one they were on (if any): the first in line after it, or the first.
  def self.next_for(user, after: nil, skip: [])
    ships = open_to(user, skip: [ *skip, after&.id ].compact)
    later = ships.where("(ships.created_at, ships.id) > (?, ?)", after.created_at, after.id) if after
    later&.first || ships.first
  end
end
