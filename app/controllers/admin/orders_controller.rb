# Every console claimed with approved hours (Order): waiting to be ordered first, oldest at the top, then ordered.
# Order it from where it says, then mark it ordered here; Clippy tells them (OrderNotifier).
class Admin::OrdersController < Admin::BaseController
  def index
    @waiting = Order.waiting.includes(project: :user).order(:created_at)
    @ordered = Order.ordered.includes(:ordered_by, project: :user).order(ordered_at: :desc)
  end

  def update
    order = Order.find(params[:id])
    ordered = order.ordered!(by: current_user)
    redirect_to admin_orders_path, alert: ("That one's been ordered already." unless ordered)
  end
end
