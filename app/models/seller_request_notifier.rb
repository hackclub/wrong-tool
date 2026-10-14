# Telling people on Slack about asking for another seller (SellerRequest): the admins when someone asks (the link,
# and a button to decide), and Clippy's DM to them once it's decided, a plain line then how he feels, like
# ExtensionNotifier.
module SellerRequestNotifier
  # To each admin. Their real name's fine here: it's a DM to an admin, not #wrong.
  ADMIN_DM = "%{name} found the %{console} at another seller, to save on customs:\n%{url}"

  DMS = {
    "approved" => "We checked your link for the %{console}. If it's your pick, it'll come from %{host}.\n" \
                  ":clippy-excited: clippy is doing a little dance. :dino-bbq:",
    "denied" => "We can't use %{host} for the %{console}, so it'll come from %{vendor}. You can send another link.\n" \
                ":clippy-hopeful: clippy is still rooting for you. :blob-wiggle:"
  }.freeze

  def self.requested(ask)
    user = ask.project.user
    text = format(ADMIN_DM, name: user.name.presence || user.public_name, console: ask.console.full, url: ask.url)
    Rails.configuration.x.admin_slack_ids.each do |slack_id|
      SlackMessageJob.perform_later(slack_id, text, link: [ "Decide on wrong tool", "#{Rails.configuration.x.app_url}/admin/seller_requests" ])
    end
  end

  # Noted as Clippy's latest DM as it's queued (User#slack_dmed!), so a nudge in the same hour holds off. Nothing if
  # they're not on Slack or stopped his messages.
  def self.decided(ask)
    user = ask.project.user
    return if user.slack_id.blank? || user.slack_muted_at.present?

    user.slack_dmed!
    text = format(DMS.fetch(ask.status), console: ask.console.full, host: ask.host, vendor: ask.console.vendor.name)
    SlackMessageJob.perform_later(user.slack_id, text, link: [ "Open the shop", "#{Rails.configuration.x.app_url}/shop" ])
  end
end
