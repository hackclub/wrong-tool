# Everyone who's asked for a console from another seller (SellerRequest): waiting first, oldest at the top, then
# decided. Approve or deny here; Clippy tells them either way (SellerRequestNotifier).
class Admin::SellerRequestsController < Admin::BaseController
  def index
    @pending = SellerRequest.pending.includes(project: :user).order(:created_at)
    @decided = SellerRequest.decided.includes(:decided_by, project: :user).order(decided_at: :desc)
  end

  def update
    ask = SellerRequest.find(params[:id])
    decided = ask.decide!(params[:decision].to_s, by: current_user)
    redirect_to admin_seller_requests_path, alert: ("That one's been decided already." unless decided)
  end
end
