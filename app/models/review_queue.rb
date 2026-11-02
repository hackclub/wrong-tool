# The two queues' order, and what's next in them.
#
#   review  ships in review a reviewer hasn't approved (that's waiting on the fraud check) or sent on, oldest first:
#           a reship joins at the back, since it's a new ship. Admins also see the ones sent to an admin, first.
#   fraud   ships in review the fraud check hasn't scored, from the moment they're shipped: the ones a reviewer sent to
#           fraud first, then oldest first.
#
# Next is the first in line after the ship you were on (wrapping round to the front; the front, if it's left the
# queue), less the ones someone else is on, your own and the ones you skipped since you were last at the queue. In the fraud queue it never opens one a
# reviewer sent there: those are opened from the list, note and all.
module ReviewQueue
  QUEUES = ReviewDecision::QUEUES

  def self.waiting(queue, user)
    ships = Ship.in_review
    if queue == "fraud"
      ships.where(fraud_status: "unchecked").order(Arel.sql("CASE WHEN ships.review_hold = 'fraud' THEN 0 ELSE 1 END"), :created_at, :id)
    else
      ships = ships.where(review_approved_at: nil)
      if user.admin?
        ships.where(review_hold: [ nil, "admin" ]).order(Arel.sql("CASE WHEN ships.review_hold = 'admin' THEN 0 ELSE 1 END"), :created_at, :id)
      else
        ships.where(review_hold: nil).order(:created_at, :id)
      end
    end
  end

  def self.open_to(queue, user, skip: [])
    ships = waiting(queue, user).where.not(id: ReviewClaim.live.where(queue:).where.not(user:).select(:ship_id)).where.not(id: skip)
    ships = ships.where(review_hold: nil) if queue == "fraud"
    user.admin? ? ships : ships.joins(:project).where.not(projects: { user_id: user.id })
  end

  # The next ship for this person in this queue, after the one they were on (if any): the first in line after it, or
  # the first.
  def self.next_for(user, queue: "review", after: nil, skip: [])
    ships = open_to(queue, user, skip: [ *skip, after&.id ].compact).to_a
    line = waiting(queue, user).ids
    from = after && line.index(after.id)
    return ships.first unless from

    ships.find { |ship| line.index(ship.id).to_i > from } || ships.first
  end
end
