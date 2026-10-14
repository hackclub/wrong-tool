require "test_helper"

class SellerRequestTest < ActiveSupport::TestCase
  test "a link to a listing, for a console in the shop, that isn't where it comes from already" do
    project = projects(:orpheus)
    ask = project.seller_requests.build(prize: "miyoo", url: "  https://www.aliexpress.com/item/miyoo-mini-plus.html ")
    assert ask.save
    assert_equal "https://www.aliexpress.com/item/miyoo-mini-plus.html", ask.url
    assert_equal "aliexpress.com", ask.host
    assert ask.pending?
    assert_equal Console.find("miyoo"), ask.console

    not_a_link = project.seller_requests.build(prize: "rg35xx", url: "my cousin's shop")
    assert_not not_a_link.valid?
    assert_equal "that isn't a link to a listing", not_a_link.problem

    own_store = project.seller_requests.build(prize: "rg35xx", url: "https://anbernic.com/products/rg35xxpro")
    assert_not own_store.valid?
    assert_equal "that is Anbernic's store, where it comes from already", own_store.problem

    assert_not project.seller_requests.build(prize: "switch", url: "https://example.com/switch").valid?
  end

  test "one live ask a console: another after a no, not while one's waiting or approved" do
    project = projects(:orpheus)
    first = project.seller_requests.create!(prize: "miyoo", url: "https://example.com/a")
    again = project.seller_requests.build(prize: "miyoo", url: "https://example.com/b")
    assert_not again.valid?
    assert_equal "There's a link in for the Mini Plus already", again.problem
    assert project.seller_requests.build(prize: "rg35xx", url: "https://example.com/c").valid?, "a different console's fine"

    first.decide!("denied", by: users(:ana))
    assert again.valid?
    again.save!
    again.decide!("approved", by: users(:ana))
    assert_not project.seller_requests.build(prize: "miyoo", url: "https://example.com/d").valid?
  end

  test "an admin decides once" do
    ask = projects(:ana).seller_requests.create!(prize: "rg28xx", url: "https://example.com/rg28xx")
    assert_not ask.decide!("maybe", by: users(:orpheus))
    assert ask.pending?

    travel_to Time.utc(2026, 10, 18, 15) do
      assert ask.decide!("approved", by: users(:orpheus))
    end
    assert ask.approved?
    assert_equal users(:orpheus), ask.decided_by
    assert_equal Time.utc(2026, 10, 18, 15), ask.decided_at

    assert_not ask.decide!("denied", by: users(:orpheus))
    assert ask.reload.approved?
  end
end
