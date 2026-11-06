# What a reviewer sees about a ship besides what was submitted, gathered by ShipEvidenceJob once it's shipped (and
# again on Resync), so the review page never waits on anyone else:
#
#   hackatime   its sessions on the ship's Hackatime projects, from Program::HACKATIME_START to the ship: time a day
#               (in the maker's timezone), the long ones, time after the last commit, and what Hackatime itself
#               makes of the maker's hours (its trust level)
#   repo        the GitHub repo (or that it isn't on GitHub, or isn't there), its README, and the commits in the
#               same window
#   demo        whether the demo link opens (DemoProbe)
#   lapse       the maker's Lapse timelapses of the ship's Hackatime projects since the project's last approved ship,
#               to watch it being built (Lapse), and how much of the Hackatime time over the same stretch they cover
#   duplicates  other projects' ships with the same repo or demo link
#
# Each source says how it went (sources: "ok", or why not), and the flags are worked out again from it (ShipFlag).
class ShipEvidence < ApplicationRecord
  # A session at least this long is listed; one this long is a marathon (ShipFlag).
  LONG_SESSION = 1.hour

  belongs_to :ship

  def pending? = status == "pending"
  def built? = status == "built"

  # Asks for it to be gathered, unless it was asked for in the last few minutes and hasn't come yet.
  # Every ship waiting in review or on the fraud check gathered again (Resync, for all of them), say once a new source
  # comes in. Returns those ships.
  def self.request_waiting
    Ship.in_review.order(:id).to_a.each { |ship| request(ship) }
  end

  def self.request(ship)
    evidence = find_or_initialize_by(ship:)
    return evidence if evidence.persisted? && evidence.pending? && evidence.updated_at > 5.minutes.ago

    evidence.update!(status: "pending", updated_at: Time.current)
    ShipEvidenceJob.perform_later(ship)
    evidence
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Gathers it all now, then the flags.
  def self.build!(ship)
    evidence = find_or_create_by!(ship:)
    sources = {}
    data = {
      "hackatime" => gather(sources, "hackatime") { hackatime(ship) },
      "trust" => trust(ship.project.user, sources),
      "repo" => gather(sources, "github") { repo(ship) },
      "demo" => gather(sources, "demo") { demo(ship) },
      "lapse" => (gather(sources, "lapse") { lapse(ship) } if Lapse.configured?),
      "duplicates" => duplicates(ship)
    }
    add_time_after_commits(data)
    add_lapse_coverage(data)
    evidence.update!(status: "built", data:, sources:, built_at: Time.current, error: nil)
    ShipFlag.raise_for(ship, data, sources)
    evidence
  rescue StandardError => error
    evidence&.update!(status: "failed", error: "#{error.class}: #{error.message}")
    raise
  end

  # One source: what it found, and "ok" (or why it couldn't) in sources.
  def self.gather(sources, name)
    result = yield
    sources[name] = "ok"
    result
  rescue Hackatime::NotLinked
    sources[name] = "Hackatime isn't linked"
    nil
  rescue Hackatime::Expired
    sources[name] = "Hackatime stopped accepting their token"
    nil
  rescue Hackatime::Unavailable, Github::Unavailable, Lapse::Unavailable => error
    sources[name] = "couldn't be reached (#{error.message})"
    nil
  end

  def self.window(ship)
    zone = ship.project.user.time_zone
    Program::HACKATIME_START.in_time_zone(zone)..ship.created_at
  end

  def self.hackatime(ship)
    user = ship.project.user
    window = window(ship)
    return { "tracked_seconds" => 0, "days" => {}, "long_sessions" => [], "longest_seconds" => 0, "sessions" => [] } if ship.hackatime_projects.empty?

    spans = Hackatime.heartbeat_spans(user, ship.hackatime_projects, start_date: Program::HACKATIME_START - 1,
                                                                     end_date: ship.created_at.utc.to_date + 2)
    sessions = spans.filter_map do |span|
      starts = [ Time.zone.at(span["start_time"].to_f), window.begin ].max
      ends = [ Time.zone.at(span["end_time"].to_f), window.end ].min
      seconds = [ (ends - starts).round, span["duration"].to_i ].min
      { "start" => starts.iso8601, "end" => ends.iso8601, "seconds" => seconds } if seconds.positive?
    end

    days = Hash.new(0)
    sessions.each { |session| days[Time.zone.parse(session["start"]).in_time_zone(user.time_zone).to_date.iso8601] += session["seconds"] }
    long = sessions.select { |session| session["seconds"] >= LONG_SESSION }.sort_by { |session| -session["seconds"] }

    { "tracked_seconds" => sessions.sum { |session| session["seconds"] }, "days" => days.sort.to_h,
      "long_sessions" => long.first(20), "longest_seconds" => long.first&.dig("seconds").to_i,
      "sessions" => sessions.sort_by { |session| session["start"] }, "timezone" => user.time_zone.tzinfo.identifier }
  end

  # What Hackatime makes of their hours now (Hackatime.trust), kept on them too so it's the latest anyone's seen. A
  # source of its own, so it's there even when their hours can't be read (their token's stopped working: the admin key
  # doesn't need it). If Hackatime won't say this time, a reviewer gets the last call we were told, marked as not asked
  # just now; never linked, there's none.
  # How the asking went is noted with the other sources ("hackatime_trust"), so a reviewer sees why there's none.
  def self.trust(user, sources)
    level = Hackatime.trust(user)
    sources["hackatime_trust"] = level.present? ? "ok" : "Hackatime gave no trust level for Hackatime user #{user.hackatime_uid}"
    user.note_hackatime_trust!(level)
    { "trust_level" => level, "trust_checked_at" => Time.current.iso8601 }
  rescue Hackatime::Expired, Hackatime::Unavailable => error
    via = Rails.configuration.x.hackatime_admin_api_key ? "the admin key" : "their token, since there's no admin key here"
    sources["hackatime_trust"] = error.is_a?(Hackatime::Expired) ? "Hackatime wouldn't take #{via}" : "couldn't be reached with #{via} (#{error.message})"
    { "trust_level" => user.hackatime_trust_level, "trust_checked_at" => user.hackatime_trust_checked_at&.iso8601,
      "trust_stale" => true }
  rescue Hackatime::NotLinked
    nil
  end

  def self.repo(ship)
    name = Github.repo_name(ship.repo_url)
    return { "on_github" => false } unless name

    repo = Github.repo(name)
    return { "on_github" => true, "name" => name, "missing" => true } unless repo

    window = window(ship)
    commits = Github.commits(repo.full_name, since: window.begin, until_time: window.end)
    { "on_github" => true, "name" => repo.full_name, "missing" => false, "created_at" => repo.created_at&.iso8601,
      "pushed_at" => repo.pushed_at&.iso8601, "fork" => repo.fork, "parent" => repo.parent, "stars" => repo.stars,
      "readme" => Github.readme?(repo.full_name),
      "commits" => commits.map { |commit| { "sha" => commit.sha, "message" => commit.message, "author" => commit.author_name,
                                            "login" => commit.author_login, "at" => commit.at.iso8601, "url" => commit.url } },
      "commit_authors" => commits.map { |commit| commit.author_login || commit.author_name }.compact.tally }
  end

  def self.demo(ship)
    result = DemoProbe.check(ship.demo_url)
    { "status" => result.status, "error" => result.error, "reachable" => result.reachable? }
  end

  # The maker's Lapse timelapses of what this ship's hours were logged against (Lapse), found by their Hackatime ID.
  # Only those since the project's last approved ship: what came before was that ship's, and a ship after changes were
  # asked for is the same work, so its recordings count again. Lapse only says when one was made, not when the
  # recording started, so that's what goes by. Ones made after this ship are kept, marked, since a recording is often
  # published once it's done. Stored as they came: the video link is signed and goes stale, so a reviewer gets the
  # watch page too, and Resync fetches fresh ones.
  def self.lapse(ship)
    uid = ship.project.user.hackatime_uid
    raise Hackatime::NotLinked if uid.blank?

    since = ship.project.ships.approved.where(id: ...ship.id).maximum(:created_at)
    all = Lapse.timelapses(uid, ship.hackatime_projects)
    kept = all.select { |timelapse| since.nil? || timelapse.recorded_at.nil? || timelapse.recorded_at > since }
    { "since" => since&.iso8601, "earlier" => all.size - kept.size,
      "seconds" => kept.sum { |timelapse| timelapse.recorded_at.nil? || timelapse.recorded_at <= ship.created_at ? timelapse.seconds : 0 },
      "timelapses" => kept.map { |timelapse| timelapse.to_h_for_evidence.merge("after_ship" => timelapse.recorded_at.present? && timelapse.recorded_at > ship.created_at) } }
  end

  # Hackatime's time over the same stretch as the Lapse recordings (since the last approved ship, to this one), to
  # set what was recorded against what was tracked. Lapse sends its time to Hackatime, so for a project built on
  # Lapse the two should be close.
  def self.add_lapse_coverage(data)
    lapse = data["lapse"]
    sessions = data.dig("hackatime", "sessions")
    return unless lapse && sessions

    since = lapse["since"] && Time.zone.parse(lapse["since"])
    lapse["hackatime_seconds"] = sessions.sum do |session|
      next session["seconds"] if since.nil?

      starts = [ Time.zone.parse(session["start"]), since ].max
      ends = Time.zone.parse(session["end"])
      ends > starts ? [ (ends - starts).round, session["seconds"] ].min : 0
    end
  end

  # Other projects' ships with this repo or demo link, however it's written (case, a trailing slash or .git, www).
  def self.duplicates(ship)
    links = { "repo" => same_link(ship.repo_url), "demo" => same_link(ship.demo_url) }
    Ship.includes(:project).where.not(project_id: ship.project_id).filter_map do |other|
      matched = links.select { |field, link| link.present? && [ same_link(other.repo_url), same_link(other.demo_url) ].include?(link) }.keys
      { "ship_id" => other.id, "title" => other.title, "project_id" => other.project_id, "status" => other.status, "links" => matched } if matched.any?
    end
  end

  def self.same_link(url)
    url.to_s.strip.downcase.sub(%r{\Ahttps?://(www\.)?}, "").delete_suffix("/").delete_suffix(".git").presence
  end

  # Hackatime time after the last commit in the window: building nobody committed.
  def self.add_time_after_commits(data)
    commits = data.dig("repo", "commits")
    sessions = data.dig("hackatime", "sessions")
    return unless commits.present? && sessions

    last = commits.map { |commit| Time.zone.parse(commit["at"]) }.max
    data["hackatime"]["after_last_commit_seconds"] = sessions.sum do |session|
      starts = [ Time.zone.parse(session["start"]), last ].max
      ends = Time.zone.parse(session["end"])
      ends > starts ? [ (ends - starts).round, session["seconds"] ].min : 0
    end
  end

  private_class_method :gather, :window, :hackatime, :trust, :repo, :demo, :lapse, :duplicates, :same_link,
                       :add_time_after_commits, :add_lapse_coverage
end
