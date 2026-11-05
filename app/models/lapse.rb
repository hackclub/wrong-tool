require "net/http"

# Lapse, where someone records themselves building and ties the recording to a Hackatime project. For a ship's
# reviewer (ShipEvidence): the timelapses the maker has on Lapse whose Hackatime project is one the ship's hours came
# from, so what we were told they built can be watched being built. Never shown to the maker.
#
# It answers to a program key (config/initializers/lapse.rb), which is what lets us look someone up by their email and
# see an unlisted timelapse's Hackatime project. With no key, there's nothing here: every call comes back empty.
module Lapse
  Timelapse = Data.define(:id, :name, :hackatime_project, :page_url, :playback_url, :thumbnail_url, :seconds, :recorded_at, :visibility) do
    def to_h_for_evidence
      { "id" => id, "name" => name, "hackatime_project" => hackatime_project, "page_url" => page_url,
        "playback_url" => playback_url, "thumbnail_url" => thumbnail_url, "seconds" => seconds,
        "recorded_at" => recorded_at&.iso8601, "visibility" => visibility }
    end
  end

  # Lapse couldn't be reached, or answered something we can't use. A reviewer sees that it couldn't be read, and
  # Resync asks again; it never holds up a review.
  class Unavailable < StandardError; end

  # Tests set this instead of asking the real Lapse: { email => [ Timelapse, ... ] }. Anyone not in it has none.
  mattr_accessor :stubbed

  def self.configured?
    !stubbed.nil? || Rails.configuration.x.lapse_program_key.present?
  end

  # The maker's timelapses for these Hackatime projects, newest first. Empty if Lapse isn't set up here, we don't know
  # their email, the ship has no Hackatime project, or Lapse has nobody with that email.
  def self.timelapses(email, project_names)
    names = project_names.to_a.map(&:to_s).compact_blank
    return [] if email.blank? || names.empty? || !configured?

    theirs = stubbed ? stubbed.fetch(email, []) : of_user(user_id(email))
    theirs.select { |timelapse| names.include?(timelapse.hackatime_project) }
          .sort_by { |timelapse| -(timelapse.recorded_at&.to_i || 0) }
  end

  # Who they are on Lapse, by the email Hack Club Auth gave us (Lapse matches it as it's written). Nil if Lapse has
  # nobody with it. Cached briefly, since a queue of ships asks for the same people over and over.
  def self.user_id(email)
    Rails.cache.fetch([ "lapse/user", email ], expires_in: 5.minutes) do
      body = get("/api/user/queryByEmail?#{{ email: }.to_query}", allow_missing: true)
      data(body)&.dig("user", "id")&.to_s.presence
    end
  end

  def self.of_user(user_id)
    return [] if user_id.blank?

    data(get("/api/timelapse/findByUser?#{{ user: user_id }.to_query}"))&.dig("timelapses").to_a.filter_map do |raw|
      next unless raw.is_a?(Hash) && raw["id"].present?

      # A program key gets the private fields; which shape they come in has moved before, so take either.
      project = raw.dig("private", "hackatimeProject") || raw["hackatimeProject"]
      Timelapse.new(id: raw["id"].to_s, name: raw["name"].to_s, hackatime_project: project.presence&.to_s,
                    page_url: page_url(raw["id"]), playback_url: raw["playbackUrl"].presence,
                    thumbnail_url: raw["thumbnailUrl"].presence, seconds: raw["duration"].to_f.round,
                    recorded_at: at(raw["createdAt"]), visibility: raw["visibility"].presence)
    end
  end

  # Where to watch it. Unlike playbackUrl, which is a signed link that goes stale, this one keeps working, so it's
  # what a reviewer gets if the video itself won't play.
  def self.page_url(id)
    "#{Rails.configuration.x.lapse_url}/timelapse/#{ERB::Util.url_encode(id)}"
  end

  # Lapse's dates are milliseconds since the epoch.
  def self.at(milliseconds)
    Time.zone.at(milliseconds.to_f / 1000) if milliseconds.to_f.positive?
  end

  # Everything Lapse answers is { "ok" => true, "data" => … } or { "ok" => false, "error" =>, "message" => }.
  def self.data(body)
    return unless body.is_a?(Hash)
    raise Unavailable, "Lapse said #{body["error"]} (#{body["message"]})" unless body["ok"]

    body["data"]
  end

  def self.get(path, allow_missing: false)
    uri = URI("#{Rails.configuration.x.lapse_url}#{path}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "Authorization" => "Bearer #{Rails.configuration.x.lapse_program_key}", "Accept" => "application/json")
    end
    return if allow_missing && response.is_a?(Net::HTTPNotFound)
    raise Unavailable, "Lapse answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end
  private_class_method :user_id, :of_user, :at, :data, :get
end
