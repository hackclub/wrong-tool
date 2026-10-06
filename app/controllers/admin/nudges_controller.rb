# The bandit dashboard: how Clippy's nudges are doing and what the bandit's learned (Nudge::Stats). Anyone who
# isn't an admin gets a not found.
class Admin::NudgesController < ApplicationController
  before_action do
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false unless current_user&.admin?
  end

  def index
    @stats = Nudge::Stats.new
  end
end
