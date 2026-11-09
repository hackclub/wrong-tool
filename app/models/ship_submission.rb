# A decided ship, as Hack Club's Unified YSWS wants it: a row in the "YSWS - Wrong" base's YSWS Project Submission
# table (Airtable), one per ship, keyed by Submission Key, so sending it again updates it. ShipSubmissionJob sends a
# ship once it's decided and whenever its decision changes; the sweep (ShipSubmissionJob with no ship) catches what
# couldn't be sent.
#
# Approved (the review approved it and it passed the fraud check) goes with the hours it adds to the project and why:
# the reviewer's justification, the deflation reason, the fraud check's score and note, the Hackatime projects and
# dates, and the Lapse recordings. It's ticked "Automation - Submit to Unified YSWS" only once the record has their
# address and birthday (NEEDED), whether from us or filled in on Airtable; until then it waits there, unticked, and
# the sweep looks again. Rejected, by a reviewer or the fraud check, ticks Rejected with the reason, and never goes to
# the automation. In review or asked for changes, it isn't sent at all.
module ShipSubmission
  KEY_PREFIX = "wrong-tool-ship-"

  SUBMIT = "Automation - Submit to Unified YSWS"
  # What Unified YSWS needs about the maker before it's sent there: as the record has it on Airtable, which may be from
  # us or filled in there by hand.
  NEEDED = [ "Address (Line 1)", "City", "ZIP / Postal Code", "Country", "Birthday" ].freeze

  def self.sendable?(ship) = ship.approved? || ship.rejected?

  # Sends it, then ticks it for Unified YSWS if it's approved and past the fraud check and the record has everything
  # NEEDED (or unticks it, if not), and notes it was sent. Nothing if it's not decided, or there's no Airtable token here.
  def self.sync!(ship)
    return unless Airtable.configured? && sendable?(ship)

    started = Time.current
    record = Airtable.upsert(fields(ship), merge_on: "Submission Key")
    submit = submittable?(ship) && complete?(record["fields"])
    Airtable.update(record["id"], SUBMIT => submit) unless record["fields"][SUBMIT].present? == submit
    ship.update_columns(airtable_record_id: record["id"], airtable_synced_at: started,
                        airtable_submitted_at: submit ? ship.airtable_submitted_at || started : nil)
    record["id"]
  end

  def self.submittable?(ship) = ship.approved? && ship.fraud_passed?

  # Everything NEEDED is on the record.
  def self.complete?(fields)
    NEEDED.all? { |name| fields[name].to_s.strip.present? }
  end

  # Decided ships that have never been sent, or changed since, and approved ones not ticked for Unified YSWS yet (their
  # address or birthday might be on the record now).
  def self.unsynced
    decided = Ship.where(status: %w[approved rejected])
    decided.where("airtable_synced_at IS NULL OR airtable_synced_at < ships.updated_at")
           .or(decided.where(status: "approved", fraud_status: %w[good sus], airtable_submitted_at: nil)).order(:id)
  end

  def self.fields(ship)
    user = ship.project.user
    address = user.address || {}
    approved = submittable?(ship)
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
      # Only what we have: a blank never wipes an address or birthday filled in on Airtable from somewhere else.
      **{
        "Address (Line 1)" => address["street_address"],
        "City" => address["locality"],
        "State / Province" => address["region"],
        "ZIP / Postal Code" => address["postal_code"],
        "Country" => address["country"],
        "Birthday" => user.birthdate
      }.compact_blank,
      "Justification - Submitter Hackatime ID" => user.hackatime_uid,
      "Justification - Hackatime Project Name(s) + Date Range(s)" => hackatime_range(ship),
      "Justification - Lapse Links, comma-separated" => lapse_links(ship),
      "Rejected" => ship.rejected?,
      "Rejection Reason" => (rejection_reason(ship) if ship.rejected?),
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
      "Optional - Override Hours Spent Justification" => justification(ship, approval, granted, earlier, added),
      "Justification - Specific Technical Features" => approval&.justification,
      "Justification - Deflation Justification" => deflation(ship, approval),
      "Justification - Additional Justification" => (approval.video_url if approval&.video_url),
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

  # The case for the hours, in the template every YSWS sends Unified ([HACKATIME], [SPECIFIC TECHNICAL FEATURES],
  # [DEFLATION JUSTIFICATION], [ADDITIONAL JUSTIFICATION]), from what wrong tool gathered (ShipEvidence) and what its
  # reviewer said. It's the one field Unified reads: with the override hours set (always, from us), the base's Unified
  # Justification is this alone, not the separate Justification fields.
  def self.justification(ship, approval, granted, earlier, added)
    evidence = ship.evidence&.data || {}
    [
      section("HACKATIME", hackatime_lines(ship)),
      section("SPECIFIC TECHNICAL FEATURES", [ approval&.justification&.strip ]),
      section("DEFLATION JUSTIFICATION", [ deflation_line(ship, approval, granted) ]),
      section("ADDITIONAL JUSTIFICATION", additional_lines(ship, approval, granted, earlier, added, evidence))
    ].compact.join("\n\n")
  end

  def self.section(title, lines)
    lines = lines.compact_blank
    "[#{title}]\n#{lines.join("\n")}" if lines.any?
  end

  def self.hackatime_lines(ship)
    [
      ("Hackatime ID: #{ship.project.user.hackatime_uid}" if ship.project.user.hackatime_uid.present?),
      ("Hackatime Projects: #{hackatime_range(ship)}" if ship.hackatime_projects.present?),
      ("Lapse Links: #{lapse_links(ship)}" if lapse_links(ship))
    ]
  end

  # Fewer hours than it shipped with, and why: the reviewer's reason, or an admin's when they changed it since.
  def self.deflation_line(ship, approval, granted)
    return unless granted < ship.hours.to_f

    change = ship.review_decisions.select(&:hours_changed?).last
    "Deflated from #{fmt(ship.hours)} to #{fmt(granted)} hours: #{(change&.justification || approval&.deflation_reason).to_s.strip}"
  end

  def self.additional_lines(ship, approval, granted, earlier, added, evidence)
    shipped = ship.hours.to_f
    change = ship.review_decisions.select(&:hours_changed?).last
    reviewed_on = approval&.created_at || ship.decided_at
    repo = evidence["repo"]
    lapse = evidence["lapse"]
    earlier_ships = ship.project.ships.approved.where(id: ...ship.id).count

    [
      "Reviewed on wrong tool by #{approval&.reviewer&.name || "a reviewer"} on #{us(reviewed_on)}.",
      "Shipped on #{us(ship.created_at)}.",
      ("Hackatime: #{fmt(shipped)} hours on #{ship.hackatime_projects.join(", ")} when shipped" \
       "#{", #{fmt(shipped - earlier)} since the last approved ship" if earlier.positive?}." if ship.hackatime_projects.present?),
      if granted > shipped
        "Approved for #{fmt(granted)} hours: they kept working while it waited for review, and Hackatime had #{fmt(granted)} by then."
      elsif granted < shipped
        "Approved for #{fmt(granted)} hours (deflated from #{fmt(shipped)})."
      else
        "Approved for #{fmt(granted)} hours."
      end,
      ("The reviewer first deflated it (#{approval.deflation_reason.strip}), and the hours were restored by " \
       "#{change.reviewer&.name || "an admin"}: #{change.justification.strip}" if change && granted >= shipped && approval&.deflation_reason),
      ("Lapse: #{lapse["timelapses"].to_a.count { |timelapse| !timelapse["after_ship"] }} timelapses, " \
       "#{fmt(lapse["seconds"].to_i / 3600.0)} hours recorded." if lapse && lapse_links(ship)),
      (if repo && repo["on_github"] && !repo["missing"]
         "Commit history: #{repo["commits"].to_a.size} commits over the same stretch, #{ship.repo_url.delete_suffix(".git").delete_suffix("/")}/commits" \
           "#{"; it has a README" if repo["readme"]}."
       else
         "Code: #{ship.repo_url}"
       end),
      "Demo: #{ship.demo_url}#{" (it opened when checked)" if evidence.dig("demo", "reachable")}",
      ("Review video: #{approval.video_url}" if approval&.video_url),
      if earlier.positive?
        "Ship #{earlier_ships + 1} of this project: earlier ships were approved for #{fmt(earlier)} hours, so this counts the #{fmt(added)} since."
      else
        "First ship of this project."
      end
    ]
  end

  # From the project's last approved ship (or the start of the program) to this one.
  def self.stretch(ship)
    since = ship.project.ships.approved.where(id: ...ship.id).maximum(:created_at)&.to_date || Program::HACKATIME_START
    [ since, ship.created_at.to_date ]
  end

  def self.us(time) = time&.to_date&.strftime("%-m/%-d/%Y")

  # Why the reviewer took hours off, while it still grants fewer than it shipped with: an admin putting them back
  # makes it moot.
  def self.deflation(ship, approval)
    approval&.deflation_reason if (ship.approved_hours || ship.hours).to_f < ship.hours.to_f
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

    since, till = stretch(ship)
    ship.hackatime_projects.map { |name| "#{name} #{us(since)}-#{us(till)}" }.join(", ")
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

  private_class_method :approval_fields, :blank_approval_fields, :justification, :section, :hackatime_lines, :deflation_line,
                       :additional_lines, :stretch, :us, :deflation, :rejection_reason, :earlier_hours,
                       :hackatime_range, :lapse_links, :screenshot, :names, :github_username, :fmt
end
