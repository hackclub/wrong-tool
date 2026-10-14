# Asking for a console from another seller (SellerRequest), from the shop's counter: a link to the listing. The
# admins hear on Slack and decide on /admin/seller_requests. JSON back, with the ask as the shop shows it.
class SellerRequestsController < ApplicationController
  before_action :require_project

  def create
    ask = @project.seller_requests.build(seller_request_params)
    if ask.save
      SellerRequestNotifier.requested(ask)
      PostHog.capture(
        distinct_id: current_user.posthog_distinct_id,
        event: "seller_requested",
        properties: { prize: ask.prize, host: ask.host }
      ) if Rails.configuration.x.posthog_configured
      PosthogLog.info("seller_requested")

      render json: helpers.shop_ask_data(ask)
    else
      render json: { error: ask.problem }, status: :unprocessable_entity
    end
  end

  private
    def require_project
      @project = current_user&.project
      head :not_found unless @project
    end

    def seller_request_params
      params.expect(seller_request: [ :prize, :url ])
    end
end
