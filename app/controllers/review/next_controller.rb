# On to the next ship in a queue (ReviewQueue): from the queue, the first in line; from a ship (after=), the one after
# it. With skip=, the one you were on stays out of your picks until you're back at the queue.
class Review::NextController < Review::BaseController
  def create
    after = Ship.find_by(id: params[:after])
    skip!(after) if after && params[:skip].present?
    fraud = (queue if queue == "fraud")

    if (upcoming = ReviewQueue.next_for(current_user, queue:, after:, skip: skipped))
      redirect_to review_ship_path(upcoming, queue: fraud)
    else
      redirect_to review_root_path(queue: fraud), notice: "Nothing else is waiting on you."
    end
  end
end
