# The admin pages. Anyone who isn't an admin gets a not found, so nobody learns they're there.
class Admin::BaseController < ApplicationController
  before_action :require_admin

  private
    def require_admin
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false unless current_user&.admin?
    end
end
