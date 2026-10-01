require "net/http"

# Hackatime's public stats: the projects someone's logged time on, found by their Slack ID. Cached for a few minutes;
# Refresh on the project page fetches them again.
module Hackatime
  Project = Data.define(:name, :seconds) do
    def hours = (seconds / 3600.0).round(1)
  end

  # Hackatime doesn't know them (no Slack ID, or never signed in to Hackatime), or couldn't be reached.
  class NotFound < StandardError; end
  class Unavailable < StandardError; end

  # Tests set this to { slack_id => [ Project, ... ] } instead of asking the real Hackatime.
  mattr_accessor :stubbed_projects

  def self.projects(slack_id, refresh: false)
    raise NotFound if slack_id.blank?
    return stubbed_projects.fetch(slack_id) { raise NotFound } if stubbed_projects

    Rails.cache.fetch([ "hackatime/projects", slack_id ], expires_in: 5.minutes, force: refresh) { fetch_projects(slack_id) }
  end

  def self.fetch_projects(slack_id)
    uri = URI("#{Rails.configuration.x.hackatime_url}/api/v1/users/#{CGI.escape(slack_id)}/stats?features=projects")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri)
    end
    raise NotFound if response.is_a?(Net::HTTPNotFound)
    raise Unavailable, "Hackatime answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).dig("data", "projects").to_a.map { |project| Project.new(project["name"], project["total_seconds"].to_i) }
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError => error
    raise Unavailable, error.message
  end
  private_class_method :fetch_projects
end
