# Telling people on Slack about a claimed console (Order): the admins when someone claims (what, and a button to the
# queue), and Clippy's DM to them once it's ordered, a plain line then how he feels, like ExtensionNotifier.
module OrderNotifier
  # To each admin. Their real name's fine here: it's a DM to an admin, not #wrong.
  ADMIN_DM = "%{name} claimed the %{configuration} with %{hours} approved hours. Order it from %{seller}:\n%{url}"

  DM = "Your %{configuration} is ordered. It'll get to you from %{seller}.\n" \
       ":clippy-excited: clippy is doing a little dance. :partyparrot:"

  def self.claimed(order)
    user = order.project.user
    text = format(ADMIN_DM, name: user.name.presence || user.public_name, configuration: order.configuration,
                            hours: order.hours.to_f.round(1).to_s.delete_suffix(".0"), seller: order.seller_name, url: order.seller_url)
    Rails.configuration.x.admin_slack_ids.each do |slack_id|
      SlackMessageJob.perform_later(slack_id, text, link: [ "Open the queue", "#{Rails.configuration.x.app_url}/admin/orders" ])
    end
  end

  # Noted as Clippy's latest DM as it's queued (User#slack_dmed!). Nothing if they're not on Slack or stopped his
  # messages.
  def self.ordered(order)
    user = order.project.user
    return if user.slack_id.blank? || user.slack_muted_at.present?

    user.slack_dmed!
    text = format(DM, configuration: order.configuration, seller: order.seller_name)
    SlackMessageJob.perform_later(user.slack_id, text, link: [ "Open the shop", "#{Rails.configuration.x.app_url}/shop" ])
  end
end
