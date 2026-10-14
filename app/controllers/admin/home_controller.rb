# The admin home (/admin): what's waiting on an admin, and every admin page with what it's for (Admin::NavHelper).
class Admin::HomeController < Admin::BaseController
  def show
    @waiting = { "Orders" => Order.waiting.count, "Ships" => Ship.in_review.count, "Extensions" => Extension.pending.count, "Sellers" => SellerRequest.pending.count }
    @totals = { "Projects" => Project.count, "People" => User.count }
  end
end
