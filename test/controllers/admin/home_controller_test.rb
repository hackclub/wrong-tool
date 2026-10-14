require "test_helper"

class Admin::HomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS" ]
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "admins see what's waiting on them, and every admin page with what it's for" do
    projects(:ana).create_extension!(reason: "exams")
    projects(:ana).seller_requests.create!(prize: "miyoo", url: "https://www.amazon.de/dp/B0MIYOO")
    projects(:orpheus).seller_requests.create!(prize: "rg35xx", url: "https://shop.example/rg35xx")
    sign_in_as(users(:orpheus))
    get admin_root_path

    assert_response :success
    assert_equal "/admin", admin_root_path
    assert_select ".admin__nav a[aria-current=page]", "Admin"
    assert_equal %w[Admin Orders Ships Extensions Sellers Projects People Numbers Bandit Blazer], css_select(".admin__nav a").map(&:text)
    assert_select ".formula-bar__content", /3 waiting/
    assert_select "a.admin__tile[href=?][data-waiting]", admin_extensions_path, /Extensions\s*1\s*waiting/
    assert_select "a.admin__tile[href=?][data-waiting]", admin_seller_requests_path, /Sellers\s*2\s*waiting/
    assert_select "a.admin__tile[href=?]:not([data-waiting])", admin_ships_path, /Ships\s*0\s*in review/
    assert_select ".admin__table--pages tbody tr", 9
    assert_select ".admin__table--pages th a[href=?]", "/admin/blazer", "Blazer"
    assert_select ".admin__table--pages tr", text: /Projects.*Every project, searchable.*#{Project.count}/m

    # And it's in the nav on every admin page.
    get admin_ships_path
    assert_select ".admin__nav a[href=?]", admin_root_path, "Admin"
  end

  test "nobody else can see it" do
    get admin_root_path
    assert_response :not_found

    sign_in_as(users(:ana))
    get admin_root_path
    assert_response :not_found
  end

  private
    def sign_in_as(user)
      mock_hack_club_auth(uid: user.hca_id, slack_id: user.slack_id, email: user.email, name: user.name, first_name: user.first_name)
      post "/auth/hackclub"
      follow_redirect!
    end
end
