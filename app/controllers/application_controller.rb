class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :signed_in?, :impersonating?, :true_user

  before_action :remember_timezone

  private
    # app/javascript/timezone.js keeps the browser's timezone in a cookie. Not while an admin's viewing as someone:
    # that's the admin's browser, not theirs.
    def remember_timezone
      current_user&.remember_timezone(cookies[:timezone]) if cookies[:timezone].present? && !impersonating?
    end

    # Who the site's showing: you, or whoever an admin's viewing as (Admin::ImpersonationsController).
    def current_user
      return @current_user if defined?(@current_user)
      @current_user = User.find_by(id: session[:user_id])
    end

    def signed_in?
      current_user.present?
    end

    # An admin's seeing the site as someone else: session[:impersonator_id] is the admin, session[:user_id] who
    # they're viewing as.
    def impersonating?
      session[:impersonator_id].present? && session[:user_id].present?
    end

    # The admin behind an impersonation; otherwise whoever's signed in.
    def true_user
      return current_user unless impersonating?
      return @true_user if defined?(@true_user)
      @true_user = User.find_by(id: session[:impersonator_id])
    end
end
