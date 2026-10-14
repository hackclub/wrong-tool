require "test_helper"

class SellerRequestNotifierTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admins = Rails.configuration.x.admin_slack_ids
    Rails.configuration.x.admin_slack_ids = [ "U0ORPHEUS", "U0KARTIKEY" ]
    @ask = projects(:ana).seller_requests.create!(prize: "miyoo", url: "https://www.amazon.de/dp/B0MIYOO")
  end

  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  test "asking DMs each admin the link, with a button to decide" do
    SellerRequestNotifier.requested(@ask)

    dms = enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
    assert_equal [ "U0ORPHEUS", "U0KARTIKEY" ], dms.map { |job| job[:args].first }
    assert_equal "Ana Lovelace found the Miyoo Mini Plus at another seller, to save on customs:\nhttps://www.amazon.de/dp/B0MIYOO", dms.first[:args].second
    assert_equal [ "Decide on wrong tool", "https://wrong.hackclub.com/admin/seller_requests" ], dms.first[:args].third["link"]
  end

  test "a decision is a DM from Clippy, saying where it'll come from" do
    @ask.decide!("approved", by: users(:orpheus))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ANA" }
    assert_equal "We checked your link for the Miyoo Mini Plus. If it's your pick, it'll come from amazon.de.\n" \
                 ":clippy-excited: clippy is doing a little dance. :dino-bbq:", dm[:args].second
    assert_equal [ "Open the shop", "https://wrong.hackclub.com/shop" ], dm[:args].third["link"]
    assert_not_nil users(:ana).reload.slack_dmed_at

    clear_enqueued_jobs
    denied = projects(:orpheus).seller_requests.create!(prize: "rg35xx", url: "https://shop.example/rg35xx")
    denied.decide!("denied", by: users(:ana))
    dm = enqueued_jobs.find { |job| job[:job] == SlackMessageJob && job[:args].first == "U0ORPHEUS" }
    assert_match(/\AWe can't use shop\.example for the ANBERNIC RG35XX Pro, so it'll come from Anbernic's store\. You can send another link\./, dm[:args].second)
  end

  test "nothing to someone who stopped Clippy's messages" do
    users(:ana).update!(slack_muted_at: Time.current)
    @ask.decide!("approved", by: users(:orpheus))
    assert_empty enqueued_jobs.select { |job| job[:job] == SlackMessageJob }
  end
end
