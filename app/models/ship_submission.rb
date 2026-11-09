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

  # The case for the hours, as a reviewer would write it, from what wrong tool gathered (ShipEvidence) and what its
  # reviewer said. It's the one field Unified YSWS reads: with the override hours set (always, from us), the base's
  # Unified Justification is this alone, not the separate Justification fields.
  def self.justification(ship, approval, granted, earlier, added)
    evidence = ship.evidence&.data || {}
    [
      built(ship),
      time(ship, evidence, earlier),
      code(ship, evidence),
      recorded(ship, evidence),
      ("From the review: #{sentence(approval.justification)}" if approval&.justification),
      hours_granted(ship, approval, granted, earlier, added),
      ("There's a video of the review: #{approval.video_url}" if approval&.video_url)
    ].compact.join("\n\n")
  end

  def self.built(ship)
    maker = names(ship.project.user).first || "The maker"
    "#{maker} built #{ship.title} in #{ship.project.tool_name}, for wrong tool, where you make a game in a tool that was " \
      "never meant for games."
  end

  def self.time(ship, evidence, earlier)
    return if ship.hackatime_projects.blank?

    projects = ship.hackatime_projects.map { |name| "\"#{name}\"" }.to_sentence
    days = evidence.dig("hackatime", "days").to_h.size
    longest = evidence.dig("hackatime", "longest_seconds").to_i
    uid = ship.project.user.hackatime_uid
    text = "Hackatime#{" (user ID #{uid})" if uid.present?} tracked #{fmt(ship.hours)} hours on " \
           "#{"project".pluralize(ship.hackatime_projects.size)} #{projects} #{stretch(ship)}"
    text += earlier.zero? && days.positive? ? ", across #{days} #{"day".pluralize(days)} of work." : "."
    text += " The longest single session was #{fmt(longest / 3600.0)} hours." if longest >= ShipEvidence::LONG_SESSION
    text
  end

  def self.code(ship, evidence)
    repo = evidence["repo"]
    demo = evidence["demo"]
    parts = []
    if repo && repo["on_github"] && !repo["missing"]
      commits = repo["commits"].to_a.size
      parts << "The repo (#{ship.repo_url}) has #{commits} #{"commit".pluralize(commits)} over the same stretch" \
               "#{repo["readme"] ? " and a README" : ""}."
    else
      parts << "The code is at #{ship.repo_url}."
    end
    parts << (demo&.dig("reachable") ? "The playable link (#{ship.demo_url}) opened when it was checked." : "It's playable at #{ship.demo_url}.")
    parts.join(" ")
  end

  def self.recorded(ship, evidence)
    lapse = evidence["lapse"]
    links = lapse_links(ship)
    return unless lapse && links

    count = lapse["timelapses"].to_a.count { |timelapse| !timelapse["after_ship"] }
    "They recorded #{count} #{"timelapse".pluralize(count)} of it on Lapse, #{fmt(lapse["seconds"].to_i / 3600.0)} hours " \
      "in all: #{links}"
  end

  # How many hours it's approved for, and why, if that's not simply what it shipped with.
  def self.hours_granted(ship, approval, granted, earlier, added)
    shipped = ship.hours.to_f
    change = ship.review_decisions.select(&:hours_changed?).last
    text = if granted < shipped
      "Approved for #{fmt(granted)} of the #{fmt(shipped)} hours. #{sentence(change&.justification || approval&.deflation_reason)}".strip
    elsif granted > shipped
      "Approved for #{fmt(granted)} hours: it shipped with #{fmt(shipped)}, and they kept working on it while it waited for review."
    else
      "Approved for all #{fmt(granted)} hours."
    end
    if change && granted >= shipped && approval&.deflation_reason
      text += " The reviewer first took some off (#{approval.deflation_reason.strip.delete_suffix(".")}); on a second look they were " \
              "put back: #{sentence(change.justification)}"
    end
    text += " #{fmt(earlier)} of them were approved on this project's earlier ships, so this counts the #{fmt(added)} since." if earlier.positive?
    text
  end

  # Why the reviewer took hours off, while it still grants fewer than it shipped with: an admin putting them back
  # makes it moot.
  def self.deflation(ship, approval)
    approval&.deflation_reason if (ship.approved_hours || ship.hours).to_f < ship.hours.to_f
  end

  def self.stretch(ship)
    since = ship.project.ships.approved.where(id: ...ship.id).maximum(:created_at)&.to_date || Program::HACKATIME_START
    till = ship.created_at.to_date
    "between #{since.strftime("%b %-d")} and #{till.strftime("%b %-d, %Y")}"
  end

  # A note as a sentence: capitalised, ending in a full stop.
  def self.sentence(text)
    text = text.to_s.strip
    return text if text.empty?

    text = text.upcase_first
    text.match?(/[.!?)]\z/) ? text : "#{text}."
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

  private_class_method :approval_fields, :blank_approval_fields, :justification, :built, :time, :code, :recorded, :hours_granted,
                       :deflation, :stretch, :sentence, :rejection_reason, :earlier_hours,
                       :hackatime_range, :lapse_links, :screenshot, :names, :github_username, :fmt
end
