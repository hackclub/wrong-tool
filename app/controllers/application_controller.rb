class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :signed_in?

  before_action :remember_timezone

  private
    # app/javascript/timezone.js keeps the browser's timezone in a cookie.
    def remember_timezone
      current_user&.remember_timezone(cookies[:timezone]) if cookies[:timezone].present?
    end

    def current_user
      return @current_user if defined?(@current_user)
      @current_user = User.find_by(id: session[:user_id])
    end

    def signed_in?
      current_user.present?
    end
end
