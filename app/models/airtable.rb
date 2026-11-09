require "net/http"

# Airtable's API, for the one table we write to (config/initializers/airtable.rb): records upserted by a field that's
# unique to each, so sending one again updates it instead of adding another. With no token, nothing's sent.
module Airtable
  API_URL = "https://api.airtable.com/v0"

  # Airtable couldn't be reached, or said no. The ship's left unsynced, and the next sweep tries it again.
  class Unavailable < StandardError; end

  # Tests set this to an array instead of asking the real Airtable: each upsert's fields land in it, and it answers
  # with a record ID made from the merge field.
  mattr_accessor :stubbed

  def self.configured?
    !stubbed.nil? || Rails.configuration.x.airtable_api_key.present?
  end

  # Adds the record, or updates the one with the same value in merge_on. Its Airtable record ID.
  def self.upsert(fields, merge_on:)
    if stubbed
      stubbed << fields
      return "rec#{Digest::SHA256.hexdigest(fields[merge_on].to_s).first(14)}"
    end

    body = { performUpsert: { fieldsToMergeOn: [ merge_on ] }, typecast: true, records: [ { fields: } ] }
    patch(body).dig("records", 0, "id") or raise Unavailable, "Airtable sent no record back"
  end

  def self.patch(body)
    config = Rails.configuration.x
    uri = URI("#{API_URL}/#{config.airtable_base_id}/#{config.airtable_table_id}")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) do |http|
      http.patch(uri.request_uri, body.to_json, "Authorization" => "Bearer #{config.airtable_api_key}",
                                                "Content-Type" => "application/json")
    end
    parsed = (JSON.parse(response.body.to_s) rescue nil)
    unless response.is_a?(Net::HTTPSuccess)
      said = parsed.is_a?(Hash) ? parsed["error"].then { |error| error.is_a?(Hash) ? "#{error["type"]}: #{error["message"]}" : error } : nil
      raise Unavailable, [ "Airtable answered #{response.code}", said ].compact.join(": ")
    end
    raise Unavailable, "Airtable sent something that isn't JSON" unless parsed.is_a?(Hash)

    parsed
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end
  private_class_method :patch
end
