# The bandit dashboard: how Clippy's nudges are doing and what the bandit's learned (Nudge::Stats). Anyone who
# isn't an admin gets a not found.
class Admin::NudgesController < ApplicationController
  before_action { head :not_found unless current_user&.admin? }

  def index
    @stats = Nudge::Stats.new
  end
end
