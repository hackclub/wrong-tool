# The review pages: for admins, and anyone an admin's made a reviewer or fraud reviewer (User::REVIEW_ROLES).
# Anyone else gets a not found, as with the admin pages. Each page is in one queue (ReviewQueue): ?queue=fraud for the
# fraud check, for fraud reviewers; otherwise the review queue (or the fraud one, for someone who's only a fraud
# reviewer).
class Review::BaseController < ApplicationController
  before_action :require_review_staff
  before_action :set_queue
  helper_method :queue

  private
    def require_review_staff
      not_found unless current_user&.review_staff?
    end

    def set_queue
      @queue = params[:queue] == "fraud" || !current_user.reviewer? ? "fraud" : "review"
      not_found if @queue == "fraud" && !current_user.fraud_reviewer?
    end

    def queue = @queue

    # What you skipped in this queue since you were last at it: next and skip pass over them.
    def skipped
      session[:"#{@queue}_skipped"].to_a
    end

    def skip!(ship)
      session[:"#{@queue}_skipped"] = [ *skipped, ship.id ].uniq.last(200)
    end

    def not_found
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end
end
