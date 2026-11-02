# Everyone who's signed in, newest first, with what they pledged and where they've got to, a way to see the site
# as them (Admin::ImpersonationsController), and whether they review ships (User::REVIEW_ROLES). ?q= narrows it by
# name, email, Slack or Hack Club ID.
class Admin::UsersController < Admin::BaseController
  LIMIT = 200

  def index
    @query = params[:q].to_s.strip
    users = User.includes(:project).order(created_at: :desc)
    users = users.search(@query) if @query.present?
    @total = users.count
    @users = users.limit(LIMIT)
  end

  # Making someone a reviewer or fraud reviewer, or not. Admins are both already.
  def update
    user = User.find(params[:id])
    user.update!(review_roles: Array(params[:review_roles]).map(&:to_s) & User::REVIEW_ROLES)
    redirect_to admin_users_path(q: params[:q].presence, anchor: helpers.dom_id(user))
  end
end
