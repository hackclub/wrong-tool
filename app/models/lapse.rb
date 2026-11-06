require "net/http"

# Lapse, where someone records themselves building and ties the recording to a Hackatime project. For a ship's
# reviewer (ShipEvidence): the timelapses the maker has on Lapse for the Hackatime projects the ship's hours came from,
# so what we were told they built can be watched being built. Never shown to the maker.
#
# Lapse finds them for us by Hackatime user and project (hackatime/timelapsesForProject), so all it takes is the
# Hackatime ID we already have. It answers to a program key (config/initializers/lapse.rb, timelapse:read), which is
# what gets us the unlisted ones too; asked without one, Lapse leaves those out. With no key, there's nothing here.
module Lapse
  Timelapse = Data.define(:id, :name, :hackatime_project, :page_url, :playback_url, :thumbnail_url, :seconds, :recorded_at,
                          :visibility, :blocker) do
    def to_h_for_evidence
      { "id" => id, "name" => name, "hackatime_project" => hackatime_project, "page_url" => page_url,
        "playback_url" => playback_url, "thumbnail_url" => thumbnail_url, "seconds" => seconds,
        "recorded_at" => recorded_at&.iso8601, "visibility" => visibility, "blocker" => blocker }
    end
  end

  # Lapse couldn't be reached, or answered something we can't use. A reviewer sees that it couldn't be read, and
  # Resync asks again; it never holds up a review.
  class Unavailable < StandardError; end

  # Tests set this instead of asking the real Lapse: { hackatime_uid => [ Timelapse, ... ] }. Anyone not in it has none.
  mattr_accessor :stubbed

  def self.configured?
    !stubbed.nil? || Rails.configuration.x.lapse_program_key.present?
  end

  # The maker's timelapses for these Hackatime projects (by their exact names, as Hackatime has them), newest first.
  # Empty if Lapse isn't set up here or the ship has no Hackatime project; Lapse having nobody with that Hackatime ID is
  # empty too, as Lapse answers it.
  def self.timelapses(hackatime_uid, project_names)
    names = project_names.to_a.map(&:to_s).compact_blank.uniq
    return [] if hackatime_uid.blank? || names.empty? || !configured?

    found = if stubbed
      stubbed.fetch(hackatime_uid.to_s, []).select { |timelapse| names.include?(timelapse.hackatime_project) }
    else
      names.flat_map { |name| for_project(hackatime_uid, name) }
    end
    found.uniq(&:id).sort_by { |timelapse| -(timelapse.recorded_at&.to_i || 0) }
  end

  def self.for_project(hackatime_uid, name)
    data(get("/api/hackatime/timelapsesForProject?#{{ hackatimeUserId: hackatime_uid, projectKey: name }.to_query}"))
      &.dig("timelapses").to_a.filter_map do |raw|
        next unless raw.is_a?(Hash) && raw["id"].present?

        Timelapse.new(id: raw["id"].to_s, name: raw["name"].to_s,
                      hackatime_project: (raw.dig("private", "hackatimeProject") || name).to_s,
                      page_url: page_url(raw["id"]), playback_url: raw["playbackUrl"].presence,
                      thumbnail_url: raw["thumbnailUrl"].presence, seconds: raw["duration"].to_f.round,
                      recorded_at: at(raw["createdAt"]), visibility: raw["visibility"].presence,
                      blocker: raw["blocker"].presence)
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

  # What Lapse answers is { "ok" => true, "data" => … }, or { "ok" => false, "error" =>, "message" => } when it says no.
  def self.data(body)
    return unless body.is_a?(Hash)
    raise Unavailable, "Lapse said #{body["error"]} (#{body["message"]})" unless body["ok"]

    body["data"]
  end

  def self.get(path)
    uri = URI("#{Rails.configuration.x.lapse_api_url}#{path}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "Authorization" => "Bearer #{Rails.configuration.x.lapse_program_key}", "Accept" => "application/json")
    end
    # A key it won't take comes back as { "code" => "FORBIDDEN", "status" => 403, "message" => … }, not ok: false.
    unless response.is_a?(Net::HTTPSuccess)
      said = (JSON.parse(response.body.to_s)["message"] rescue nil)
      raise Unavailable, [ "Lapse answered #{response.code}", said ].compact.join(": ")
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end
  private_class_method :for_project, :at, :data, :get
end
