# Something odd about a ship, for its reviewer (never its maker), worked out from its evidence (ShipEvidence) each
# time that's gathered: a warning, or a red flag ("danger") that holds up approving it until someone dismisses it
# with why. A dismissal stays, even if the evidence is gathered again; a flag that's no longer true goes, unless it
# was dismissed. Thresholds are the RULES' constants.
class ShipFlag < ApplicationRecord
  SEVERITIES = %w[warn danger].freeze
  DISMISS_REASON_MIN = 10
  # A session this long without a break is a marathon; this long, or this many, is a red flag.
  MARATHON = 6.hours
  MARATHON_DANGER = 9.hours
  MARATHONS_DANGER = 3
  FEW_COMMITS = 3
  TIME_AFTER_COMMITS = 2.hours
  # A project built on Lapse (Project#lapse_tool?) whose recordings cover less than this share of Hackatime's time, once
  # there's at least LAPSE_SHORT_MIN of it.
  LAPSE_COVERAGE = 0.5
  LAPSE_SHORT_MIN = 1.hour

  belongs_to :ship
  belongs_to :dismissed_by, class_name: "User", optional: true

  validates :severity, inclusion: { in: SEVERITIES }
  validates :dismiss_reason, length: { minimum: DISMISS_REASON_MIN, too_short: "needs at least %{count} characters: why it's fine" },
                             if: :dismissed_at

  scope :open, -> { where(dismissed_at: nil) }
  scope :danger, -> { where(severity: "danger") }
  scope :by_severity, -> { order(Arel.sql("CASE severity WHEN 'danger' THEN 0 ELSE 1 END"), :created_at, :id) }

  def danger? = severity == "danger"
  def dismissed? = dismissed_at.present?

  def dismiss!(by:, reason:)
    update(dismissed_by: by, dismissed_at: Time.current, dismiss_reason: reason.to_s.strip)
  end

  # Raises the flags this evidence has, and takes down the ones it no longer has (unless they were dismissed).
  def self.raise_for(ship, data, sources)
    raised = rules(ship, data, sources)
    transaction do
      raised.each do |flag|
        record = find_or_initialize_by(ship:, kind: flag[:kind])
        record.update!(severity: flag[:severity], title: flag[:title], details: flag[:details] || {})
      end
      where(ship:).open.where.not(kind: raised.pluck(:kind)).delete_all
    end
  end

  def self.rules(ship, data, sources)
    flags = []
    time = data["hackatime"]
    trust = data["trust"] || time # it used to be kept with the hours
    repo = data["repo"]
    demo = data["demo"]
    hours = ->(seconds) { "#{(seconds / 3600.0).round(1).to_s.delete_suffix(".0")}h" }

    if sources["hackatime"] != "ok"
      flags << { kind: "hackatime_unread", severity: "warn", title: "Hackatime couldn't be read: #{sources["hackatime"]}" }
    elsif time
      marathons = time["sessions"].select { |session| session["seconds"] >= MARATHON }
      if marathons.any?
        danger = marathons.size >= MARATHONS_DANGER || marathons.any? { |session| session["seconds"] >= MARATHON_DANGER }
        flags << { kind: "marathon", severity: danger ? "danger" : "warn",
                   title: "#{marathons.size == 1 ? "A session" : "#{marathons.size} sessions"} of #{hours.(MARATHON)}+ without a break " \
                          "(longest #{hours.(marathons.map { |session| session["seconds"] }.max)})",
                   details: { "sessions" => marathons.first(10) } }
      end
      if time["after_last_commit_seconds"].to_i >= TIME_AFTER_COMMITS
        flags << { kind: "time_after_commits", severity: "warn",
                   title: "#{hours.(time["after_last_commit_seconds"])} tracked after the last commit" }
      end
    end

    # Hackatime's own call on their hours, whether or not the hours could be read. Red is Hackatime saying it's caught
    # them logging time they didn't build, so it holds up approving until someone's looked and said why it's fine.
    if trust && [ Hackatime::TRUST_UNTRUSTED, Hackatime::TRUST_SUSPECT ].include?(trust["trust_level"])
      flags << { kind: "hackatime_trust", severity: trust["trust_level"] == Hackatime::TRUST_UNTRUSTED ? "danger" : "warn",
                 title: "#{Hackatime.trust_label(trust["trust_level"])} (trust level #{trust["trust_level"]})",
                 details: { "trust_level" => trust["trust_level"], "checked_at" => trust["trust_checked_at"] } }
    end

    if sources["github"] == "ok" && repo
      if !repo["on_github"]
        flags << { kind: "external_repo", severity: "warn", title: "The repo isn't on GitHub, so its commits aren't checked" }
      elsif repo["missing"]
        flags << { kind: "repo_missing", severity: "danger", title: "The repo isn't public on GitHub (#{repo["name"]})" }
      else
        commits = repo["commits"].size
        flags << { kind: "few_commits", severity: "warn", title: "#{commits.zero? ? "No" : "Only #{commits}"} commit#{"s" unless commits == 1} since wrong tool started" } if commits < FEW_COMMITS
        flags << { kind: "no_readme", severity: "warn", title: "The repo has no README" } unless repo["readme"]
        flags << { kind: "fork", severity: "warn", title: "The repo is a fork of #{repo["parent"] || "another"}" } if repo["fork"]
        if repo["created_at"] && Time.zone.parse(repo["created_at"]).to_date < Program::HACKATIME_START
          flags << { kind: "old_repo", severity: "warn", title: "The repo's older than wrong tool (made #{Time.zone.parse(repo["created_at"]).strftime("%b %-d, %Y")})" }
        end
      end
    elsif sources["github"] != "ok"
      flags << { kind: "github_unread", severity: "warn", title: "GitHub #{sources["github"]}" }
    end

    if demo && !demo["reachable"]
      flags << { kind: "demo_unreachable", severity: "warn",
                 title: "The demo link #{demo["status"] ? "answers #{demo["status"]}" : demo["error"]}" }
    end

    # Built on Lapse, its hours should be recordings someone can watch: none, or far fewer than Hackatime has, is worth
    # a look (Hackatime time from an editor is fine; a reviewer says so). Code tools record on Lapse if they like.
    if ship.project.lapse_tool? && sources.key?("lapse")
      lapse = data["lapse"]
      if sources["lapse"] != "ok"
        # Not linked to Hackatime is hackatime_unread's to say; Lapse finds them by their Hackatime ID.
        flags << { kind: "lapse_unread", severity: "warn", title: "Lapse couldn't be read: #{sources["lapse"]}" } if ship.project.user.hackatime_uid.present?
      elsif lapse
        recorded = lapse["seconds"].to_i
        tracked = lapse["hackatime_seconds"]
        since = lapse["since"] ? "since their last approved ship" : "before the ship"
        if recorded.zero?
          flags << { kind: "lapse_missing", severity: "warn", title: "Built on Lapse, but no recordings of #{ship.hackatime_projects.to_sentence.presence || "it"} #{since}" }
        elsif tracked && tracked >= LAPSE_SHORT_MIN && recorded < tracked * LAPSE_COVERAGE
          flags << { kind: "lapse_short", severity: "warn",
                     title: "Lapse recordings cover only #{hours.(recorded)} of the #{hours.(tracked)} on Hackatime #{since}",
                     details: { "recorded_seconds" => recorded, "hackatime_seconds" => tracked } }
        end
      end
    end

    if data["duplicates"].present?
      titles = data["duplicates"].map { |other| other["title"] }.uniq.to_sentence
      flags << { kind: "duplicate", severity: "danger", title: "Another project shipped the same #{data["duplicates"].flat_map { |other| other["links"] }.uniq.to_sentence} link: #{titles}",
                 details: { "ships" => data["duplicates"] } }
    end

    flags
  end
  private_class_method :rules
end
