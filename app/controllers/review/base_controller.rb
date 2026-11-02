# The review pages: for admins, and anyone an admin's made a reviewer or fraud reviewer (User::REVIEW_ROLES).
# Anyone else gets a not found, as with the admin pages.
class Review::BaseController < ApplicationController
  before_action :require_review_staff

  private
    def require_review_staff
      not_found unless current_user&.review_staff?
    end

    def not_found
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end
end
