# Wrong tool's numbers day by day (Metric), so a change can be seen in what came after it. Anyone who isn't an
# admin gets a not found.
class Admin::MetricsController < ApplicationController
  before_action do
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false unless current_user&.admin?
  end

  def index
    @days, @values = Metric.history
  end
end
