require "net/http"

# Hackatime, where hours come from. Once you've linked it (OAuth, see HackatimeLinksController), your token gets an
# API key that reads your own stats, private or not: the projects you've logged time on since Program::HACKATIME_START. Both are cached for a
# while; Refresh on the project page asks again.
module Hackatime
  Project = Data.define(:name, :seconds) do
    def hours = (seconds / 3600.0).round(1)
  end

  # You haven't linked Hackatime, or it stopped accepting the token you linked with (link it again).
  class NotLinked < StandardError; end
  class Expired < StandardError; end
  # Hackatime couldn't be reached, or answered something we can't use.
  class Unavailable < StandardError; end

  # Tests set these instead of asking the real Hackatime: { token => Hackatime user ID } and
  # { Hackatime user ID => [ Project, ... ] }.
  mattr_accessor :stubbed_users, :stubbed_projects

  # Who a token belongs to on Hackatime, or nil.
  def self.user_id(token)
    return stubbed_users&.[](token) if stubbed_users

    response = get("/api/v1/authenticated/me", bearer: token)
    JSON.parse(response.body)["id"]&.to_s if response.is_a?(Net::HTTPSuccess)
  rescue Unavailable, JSON::ParserError
    nil
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

  def self.get(path, bearer:)
    uri = URI("#{Rails.configuration.x.hackatime_url}#{path}")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "Authorization" => "Bearer #{bearer}")
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end
  private_class_method :stats, :api_key, :get
end
