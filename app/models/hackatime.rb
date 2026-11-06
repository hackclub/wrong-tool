require "net/http"

# Hackatime, where hours come from. Once you've linked it (OAuth, see HackatimeLinksController), your token gets an
# API key that reads your own stats, private or not: the projects you've logged time on since
# Program::HACKATIME_START (to pick from; cached for a while, and Refresh on the project page asks again) and the
# spans of time you built on them (for your streak days, which every number of hours comes from: StreakActivity).
#
# The same token says who you are on Hackatime and what Hackatime makes of your hours: its trust factor (TRUST_LABELS),
# kept on you when you link and asked again whenever a ship's evidence is gathered, so a reviewer sees Hackatime's own
# call on the hours they're approving. That's for reviewers only; nobody's ever shown their own.
module Hackatime
  Project = Data.define(:name, :seconds) do
    def hours = (seconds / 3600.0).round(1)
  end

  # Who the token belongs to on Hackatime, and Hackatime's trust level for them ("red", "yellow", "blue", "green",
  # or nil if it didn't say).
  Identity = Data.define(:uid, :trust_level)

  # Hackatime's trust factor as it comes: "red" is someone it's caught logging time they didn't build, "yellow"
  # someone it has its doubts about, "blue" someone too new to have been scored, "green" someone it trusts.
  TRUST_UNTRUSTED = "red"
  TRUST_SUSPECT = "yellow"
  TRUST_LABELS = { TRUST_UNTRUSTED => "Hackatime doesn't trust their hours", TRUST_SUSPECT => "Hackatime has its doubts about them",
                   "blue" => "Hackatime hasn't scored them yet", "green" => "Hackatime trusts them" }.freeze

  def self.trust_label(level)
    TRUST_LABELS[level.to_s] || "Hackatime calls them #{level}"
  end

  # You haven't linked Hackatime, or it stopped accepting the token you linked with (link it again).
  class NotLinked < StandardError; end
  class Expired < StandardError; end
  # Hackatime couldn't be reached, or answered something we can't use.
  class Unavailable < StandardError; end

  # Tests set these instead of asking the real Hackatime: { token => Hackatime user ID },
  # { Hackatime user ID => [ Project, ... ] }, { Hackatime user ID => [ span, ... ] } and
  # { Hackatime user ID => trust level }.
  mattr_accessor :stubbed_users, :stubbed_projects, :stubbed_spans, :stubbed_trust

  # Who a token belongs to on Hackatime, and its trust level for them, or nil if Hackatime wouldn't say.
  def self.identity(token)
    if stubbed_users
      uid = stubbed_users[token]
      return Identity.new(uid:, trust_level: stubbed_trust&.[](uid)) if uid.present?
      return nil
    end

    response = get("/api/v1/authenticated/me", bearer: token)
    return unless response.is_a?(Net::HTTPSuccess)

    me = who(JSON.parse(response.body))
    Identity.new(uid: me["id"]&.to_s, trust_level: trust_level_in(me)) if me["id"].present?
  rescue Unavailable, JSON::ParserError
    nil
  end

  def self.user_id(token) = identity(token)&.uid

  # Hackatime's trust level for someone who's linked, right now, since the one kept when they linked is a snapshot and
  # Hackatime may have made its mind up since. With the admin key (config/initializers/hackatime.rb) it's the real one;
  # otherwise it's asked with the token they linked with, which Hackatime answers with yellow passed off as blue.
  # The admin key needs only who they are on Hackatime, so it answers even once their own token's stopped working.
  def self.trust(user)
    raise NotLinked if user.hackatime_uid.blank?
    return stubbed_trust&.[](user.hackatime_uid) if stubbed_users
    return admin_trust(user.hackatime_uid) if Rails.configuration.x.hackatime_admin_api_key
    raise NotLinked unless user.hackatime_linked?

    response = get("/api/v1/authenticated/me", bearer: user.hackatime_access_token)
    raise Expired if response.is_a?(Net::HTTPUnauthorized)
    raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    trust_level_in(who(JSON.parse(response.body)))
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  def self.projects(user, refresh: false)
    raise NotLinked unless user.hackatime_linked?
    return stubbed_projects.fetch(user.hackatime_uid) { raise Expired } if stubbed_projects

    Rails.cache.fetch([ "hackatime/projects", user.hackatime_uid, Program::HACKATIME_START ], expires_in: 5.minutes, force: refresh) do
      response = stats(user)
      if response.is_a?(Net::HTTPUnauthorized) # a stale API key: get a fresh one and try once more
        Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
        response = stats(user)
      end
      raise Expired if response.is_a?(Net::HTTPUnauthorized)
      raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).dig("data", "projects").to_a.map { |project| Project.new(project["name"], project["total_seconds"].to_i) }
    end
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # When you were building on these projects between two dates (end exclusive), as Hackatime's heartbeat spans:
  # { "start_time" =>, "end_time" =>, "duration" => } with times in epoch seconds. For streaks.
  def self.heartbeat_spans(user, project_names, start_date:, end_date:)
    raise NotLinked unless user.hackatime_linked?
    return stubbed_spans.fetch(user.hackatime_uid, []) if stubbed_spans

    path = spans_path(project_names, start_date:, end_date:)
    response = get(path, bearer: api_key(user))
    if response.is_a?(Net::HTTPUnauthorized) # a stale API key: get a fresh one and try once more
      Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
      response = get(path, bearer: api_key(user))
    end
    raise Expired if response.is_a?(Net::HTTPUnauthorized)
    raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["spans"].to_a
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # How many seconds you built on these projects between two times, from the spans of the days around them. For
  # telling whether one of Clippy's nudges worked (Nudge#score!).
  def self.seconds_between(user, project_names, times)
    spans = heartbeat_spans(user, project_names, start_date: times.begin.utc.to_date - 1, end_date: times.end.utc.to_date + 2)
    spans.sum do |span|
      overlap = [ span["end_time"].to_f, times.end.to_f ].min - [ span["start_time"].to_f, times.begin.to_f ].max
      overlap.positive? ? overlap : 0
    end.round
  end

  # After linking (again), so nothing cached from before sticks around.
  def self.forget(user)
    Rails.cache.delete([ "hackatime/projects", user.hackatime_uid, Program::HACKATIME_START ])
    Rails.cache.delete([ "hackatime/api_key", user.hackatime_uid ])
  end

  # Your projects, with only the time since Hackatime time started counting (so projects you haven't touched since
  # then aren't listed).
  def self.stats_path
    "/api/v1/users/my/stats?#{{ features: "projects", start_date: Program::HACKATIME_START.iso8601 }.to_query}"
  end

  # Spans on these projects between two dates. Each project goes as its own `project[]`, which Hackatime matches
  # whole: its `filter_by_project` splits on commas, so a project called "Wrong 26, Snake, GS" would match nothing.
  def self.spans_path(project_names, start_date:, end_date:)
    "/api/v1/users/my/heartbeats/spans?#{{ start_date: start_date.iso8601, end_date: end_date.iso8601, project: project_names }.to_query}"
  end

  def self.stats(user)
    get(stats_path, bearer: api_key(user))
  end

  # The OAuth token reads who you are and gets an API key; the API key reads your stats.
  def self.api_key(user)
    Rails.cache.fetch([ "hackatime/api_key", user.hackatime_uid ], expires_in: 1.week) do
      response = get("/api/v1/authenticated/api_keys", bearer: user.hackatime_access_token)
      raise Expired if response.is_a?(Net::HTTPUnauthorized)
      raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("token")
    end
  end

  # The admin API's view of them (GET /api/admin/v1/user/info_batch, read-only): their trust level as it is.
  def self.admin_trust(uid)
    response = get("/api/admin/v1/user/info_batch?#{{ ids: uid }.to_query}", bearer: Rails.configuration.x.hackatime_admin_api_key)
    raise Unavailable, "Hackatime's admin API answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    found = JSON.parse(response.body)["users"].to_a.find { |user| user["id"].to_s == uid.to_s }
    found&.dig("trust_level").presence&.to_s
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end

  # Hackatime answers /authenticated/me either way: the user, or { "data" => the user }.
  def self.who(body)
    body["data"].is_a?(Hash) ? body["data"] : body
  end

  # Its trust factor, which came as a nested object the day this was written and may yet come flat.
  def self.trust_level_in(me)
    (me.dig("trust_factor", "trust_level") || me["trust_level"]).presence&.to_s
  end

  def self.get(path, bearer:)
    uri = URI("#{Rails.configuration.x.hackatime_url}#{path}")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "Authorization" => "Bearer #{bearer}")
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end
  private_class_method :stats, :api_key, :admin_trust, :who, :trust_level_in, :get
end
