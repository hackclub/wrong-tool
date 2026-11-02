# Clippy's DM once a ship's decided (ShipReview): approved, with the hours to spend; changes asked for, with what
# and by when; or rejected, with why. The reviewer's note to the maker is quoted in it; their justification never
# is. A plain line then how he feels, like ExtensionNotifier, and noted as his latest DM (User#slack_dmed!). Nothing
# if they're not on Slack or stopped his messages: the ship page says it all too.
module ReviewNotifier
  DMS = {
    "approved" => "*%{title}* is approved. %{hours} hrs are yours to spend in the shop.%{note}\n" \
                  ":clippy-proud: clippy is quietly proud. :yay:",
    "changes_requested" => "*%{title}* needs a few changes before it can be approved:%{note}\n" \
                           "Make them and ship it again by %{due}.\n:clippy-hopeful: clippy is rooting for round two. :blob-wiggle:",
    "rejected" => "*%{title}* wasn't approved, and it can't be shipped again:%{note}\n" \
                  ":clippy-emotional: clippy is sad about this one. :crying_dino:"
  }.freeze

  LINKS = {
    "approved" => [ "Open the shop", "/shop" ],
    "changes_requested" => [ "Ship it again", "/project/ship" ],
    "rejected" => [ "Open wrong tool", "/project/ship" ]
  }.freeze

  def self.decided(ship)
    user = ship.project.user
    return if user.slack_id.blank? || user.slack_muted_at.present?

    decision = ship.verdict
    user.slack_dmed!
    text = format(DMS.fetch(ship.status), title: ship.title, note: quoted(decision&.note_to_maker),
                                          hours: hours(ship.approved_hours || ship.hours),
                                          due: ship.changes_due_at&.strftime("%b %-d"))
    label, path = LINKS.fetch(ship.status)
    SlackMessageJob.perform_later(user.slack_id, text, link: [ label, "#{Rails.configuration.x.app_url}#{path}" ])
  end

  # Each line of the note as a Slack quote, under the line that introduces it.
  def self.quoted(note)
    note.present? ? "\n" + note.lines.map { |line| ">#{line.chomp}" }.join("\n") : ""
  end

  def self.hours(hours)
    hours.to_d.round(2).to_s("F").sub(/\.0\z/, "")
  end

  private_class_method :quoted, :hours
end
