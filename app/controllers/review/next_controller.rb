# On to the next ship (ReviewQueue): from the queue, the first in line; from a ship (after=), the one after it. With
# skip=, the one you were on stays out of your picks until you're back at the queue.
class Review::NextController < Review::BaseController
  def create
    after = Ship.find_by(id: params[:after])
    session[:review_skipped] = [ *session[:review_skipped], after.id ].uniq.last(200) if after && params[:skip].present?

    if (upcoming = ReviewQueue.next_for(current_user, after:, skip: session[:review_skipped].to_a))
      redirect_to review_ship_path(upcoming)
    else
      redirect_to review_root_path, notice: "Nothing else is waiting on you."
    end
  end
end
