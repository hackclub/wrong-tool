# A decided ship, as Hack Club's Unified YSWS wants it: a row in the "YSWS - Wrong" base's YSWS Project Submission
# table (Airtable), one per ship, keyed by Submission Key, so sending it again updates it. ShipSubmissionJob sends a
# ship once it's decided and whenever its decision changes; the sweep (ShipSubmissionJob with no ship) catches what
# couldn't be sent.
#
# Approved (the review approved it and it passed the fraud check) ticks "Automation - Submit to Unified YSWS", with the
# hours it adds to the project and why: the reviewer's justification, the deflation reason, the fraud check's score and
# note, the Hackatime projects and dates, and the Lapse recordings. Rejected, by a reviewer or the fraud check, ticks
# Rejected with the reason, and never goes to the automation. In review or asked for changes, it isn't sent at all.
module ShipSubmission
  KEY_PREFIX = "wrong-tool-ship-"

  def self.sendable?(ship) = ship.approved? || ship.rejected?

  # Sends it, and notes it was sent. Nothing if it's not decided, or there's no Airtable token here.
  def self.sync!(ship)
    return unless Airtable.configured? && sendable?(ship)

    started = Time.current
    record_id = Airtable.upsert(fields(ship), merge_on: "Submission Key")
    ship.update_columns(airtable_record_id: record_id, airtable_synced_at: started)
    record_id
  end

  # Decided ships that have never been sent, or changed since.
  def self.unsynced
    Ship.where(status: %w[approved rejected]).where("airtable_synced_at IS NULL OR airtable_synced_at < ships.updated_at").order(:id)
  end

  def self.fields(ship)
    user = ship.project.user
    address = user.address || {}
    approved = ship.approved? && ship.fraud_passed?
    first, last = names(user)

    {
      "Submission Key" => "#{KEY_PREFIX}#{ship.id}",
      "Code URL" => ship.repo_url,
      "Playable URL" => ship.demo_url,
      "Description" => "#{ship.title}\n\n#{ship.description}",
      "Screenshot" => screenshot(ship),
      "First Name" => first,
      "Last Name" => last,
      "Email" => user.email,
      "GitHub Username" => github_username(ship.repo_url),
      "Slack Username" => user.slack_display_name,
      "Address (Line 1)" => address["street_address"],
      "City" => address["locality"],
      "State / Province" => address["region"],
      "ZIP / Postal Code" => address["postal_code"],
      "Country" => address["country"],
      "Birthday" => user.birthdate.presence,
      "Justification - Submitter Hackatime ID" => user.hackatime_uid,
      "Justification - Hackatime Project Name(s) + Date Range(s)" => hackatime_range(ship),
      "Justification - Lapse Links, comma-separated" => lapse_links(ship),
      "Rejected" => ship.rejected?,
      "Rejection Reason" => (rejection_reason(ship) if ship.rejected?),
      "Automation - Submit to Unified YSWS" => approved,
      **(approved ? approval_fields(ship) : blank_approval_fields)
    }
  end

  # The hours this ship adds (a reship only adds what came since the project's last approved ship), and why.
  def self.approval_fields(ship)
    approval = ship.review_decisions.select(&:approved?).last
    earlier = earlier_hours(ship)
    granted = (ship.approved_hours || ship.hours).to_f
    added = [ granted - earlier, 0 ].max.round(2)

    {
      "Optional - Override Hours Spent" => added,
      "Optional - Override Hours Spent Justification" => hours_note(ship, approval, granted, earlier, added),
      "Justification - Specific Technical Features" => approval&.justification,
      "Justification - Deflation Justification" => approval&.deflation_reason,
      "Justification - Additional Justification" => additional(ship, approval),
      "Optional - Override Duplicate Justification" =>
        (if earlier.positive?
           "An update to a project approved before in wrong tool with #{fmt(earlier)} hrs; this record counts only the " \
           "#{fmt(added)} hrs added since."
         end)
    }
  end

  def self.blank_approval_fields
    { "Optional - Override Hours Spent" => nil, "Optional - Override Hours Spent Justification" => nil,
      "Justification - Specific Technical Features" => nil, "Justification - Deflation Justification" => nil,
      "Justification - Additional Justification" => nil, "Optional - Override Duplicate Justification" => nil }
  end

  def self.hours_note(ship, approval, granted, earlier, added)
    reviewer = approval&.reviewer&.name.presence || "a reviewer"
    note = "Reviewed in wrong tool by #{reviewer} on #{approval&.created_at&.to_date&.iso8601 || ship.decided_at&.to_date&.iso8601}: " \
           "approved #{fmt(granted)} hrs of the #{fmt(ship.hours)} it shipped with."
    note += " #{fmt(earlier)} hrs were approved on earlier ships, so this adds #{fmt(added)}." if earlier.positive?
    hours_changes = ship.review_decisions.select(&:hours_changed?)
    note += " An admin changed the hours since: #{hours_changes.last.justification}" if hours_changes.any?
    note
  end

  # The fraud check, and anything else a reviewer left for staff.
  def self.additional(ship, approval)
    fraud = ship.review_decisions.select(&:fraud?).last
    [
      ("Fraud check: passed#{" (marked sus)" if ship.fraud_status == "sus"}, trust #{fraud.trust_score}/10. #{fraud.justification}".strip if fraud),
      ("Review video: #{approval.video_url}" if approval&.video_url)
    ].compact.join("\n\n").presence
  end

  def self.rejection_reason(ship)
    verdict = ship.verdict
    if verdict&.decision == "fraud_fail"
      "Failed the fraud check (trust #{verdict.trust_score}/10). #{verdict.justification}".strip
    else
      verdict&.note_to_maker.presence || "Rejected in review."
    end
  end

  # The project's approved hours from its ships before this one.
  def self.earlier_hours(ship)
    ship.project.ships.approved.where(id: ...ship.id).map { |other| (other.approved_hours || other.hours).to_f }.max.to_f
  end

  # The ship's Hackatime projects, from the last approved ship (or the start of the program) to this one.
  def self.hackatime_range(ship)
    return if ship.hackatime_projects.blank?

    since = ship.project.ships.approved.where(id: ...ship.id).maximum(:created_at)&.to_date || Program::HACKATIME_START
    "#{ship.hackatime_projects.join(", ")}: #{since.iso8601} to #{ship.created_at.to_date.iso8601}"
  end

  def self.lapse_links(ship)
    ship.evidence&.data&.dig("lapse", "timelapses").to_a.reject { |timelapse| timelapse["after_ship"] }
        .filter_map { |timelapse| timelapse["page_url"] }.join(", ").presence
  end

  def self.screenshot(ship)
    return [] unless ship.screenshot.attached?

    [ { "url" => Rails.application.routes.url_helpers.rails_blob_url(ship.screenshot, host: Rails.configuration.x.app_url),
        "filename" => ship.screenshot.filename.to_s } ]
  end

  def self.names(user)
    full = user.name.to_s.strip
    first = user.first_name.presence || full.split.first
    last = first && full.start_with?(first) ? full.delete_prefix(first).strip : full.split[1..]&.join(" ")
    [ first, last.presence ]
  end

  def self.github_username(url)
    url.to_s[%r{\Ahttps?://(?:www\.)?github\.com/([^/?#]+)}i, 1]
  end

  def self.fmt(hours) = hours.to_f.round(2).to_s.delete_suffix(".0")

  private_class_method :approval_fields, :blank_approval_fields, :hours_note, :additional, :rejection_reason, :earlier_hours,
                       :hackatime_range, :lapse_links, :screenshot, :names, :github_username, :fmt
end
