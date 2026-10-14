# Telling people on Slack about an extension (Extension): the admins when someone asks (why, and a button to decide),
# and Clippy's DM to them once it's decided. Clippy's DMs are a plain line then how he feels, with Hack Club Slack's
# emotes (so they only mean anything there), like Project::AUTO_LINKED_DM.
module ExtensionNotifier
  # To each admin. Their real name's fine here: it's a DM to an admin, not #wrong.
  ADMIN_DM = "%{name} asked for #{Program::EXTENSION_DAYS} more days on *%{title}*, built in %{tool}:\n>%{reason}"

  DMS = {
    "approved" => "#{Program::EXTENSION_DAYS} more days. *%{title}* is due %{deadline} now. Ship it whenever it's playable.\n" \
                  ":clippy-excited: clippy is doing a little dance. :dino-bbq:",
    "denied" => "No extra days this time, so *%{title}* is still due %{deadline}. Whatever it is by then, ship it.\n" \
                ":clippy-hopeful: clippy is rooting for you. :blob-wiggle:"
  }.freeze

  def self.requested(extension)
    project = extension.project
    user = project.user
    text = format(ADMIN_DM, name: user.name.presence || user.public_name, title: project.title, tool: project.tool_name,
                            reason: extension.reason)
    Rails.configuration.x.admin_slack_ids.each do |slack_id|
      SlackMessageJob.perform_later(slack_id, text, link: [ "Decide on wrong tool", "#{Rails.configuration.x.app_url}/admin/extensions" ])
    end
  end

  # Noted as Clippy's latest DM as it's queued (User#slack_dmed!), like Project#dm_about_auto_link, so a nudge in the
  # same hour holds off. Nothing if they're not on Slack or stopped his messages.
  def self.decided(extension)
    project = extension.project.reload # so its deadline sees the decision
    user = project.user
    return if user.slack_id.blank? || user.slack_muted_at.present?

    user.slack_dmed!
    text = format(DMS.fetch(extension.status), title: project.title, deadline: project.deadline.strftime("%b %-d"))
    SlackMessageJob.perform_later(user.slack_id, text, link: [ "Open wrong tool", "#{Rails.configuration.x.app_url}/project" ])
  end
end
