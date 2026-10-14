# Spending approved hours on a console (Order), from the shop's counter: any tile they cover, as it's set up there.
# The admins hear on Slack and order it from /admin/orders. JSON back, with what's left to spend.
class OrdersController < ApplicationController
  before_action :require_project

  def create
    order = @project.orders.build(order_params)
    unless order.save
      return render json: { error: order.problem }, status: :unprocessable_entity
    end

    OrderNotifier.claimed(order)
    PostHog.capture(
      distinct_id: current_user.posthog_distinct_id,
      event: "prize_claimed",
      properties: { prize: order.prize, prize_color: order.prize_color, prize_options: order.prize_options, hours: order.hours.to_f }
    ) if Rails.configuration.x.posthog_configured
    PosthogLog.info("prize_claimed")

    render json: helpers.shop_order_data(@project.reload, order)
  end

  private
    def require_project
      @project = current_user&.project
      head :not_found unless @project
    end

    def order_params
      params.expect(order: [ :prize, :prize_color, prize_options: {} ])
    end
end
