# Wrong tool's numbers day by day (Metric), so a change can be seen in what came after it.
class Admin::MetricsController < Admin::BaseController
  def index
    @days, @values = Metric.history
  end
end
