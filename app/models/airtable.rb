require "net/http"

# Airtable's API, for the one table we write to (config/initializers/airtable.rb): records upserted by a field that's
# unique to each, so sending one again updates it instead of adding another. With no token, nothing's sent.
module Airtable
  API_URL = "https://api.airtable.com/v0"

  # Airtable couldn't be reached, or said no. The ship's left unsynced, and the next sweep tries it again.
  class Unavailable < StandardError; end

  # Tests set this to an Airtable::Stub instead of asking the real Airtable: it keeps the records, as Airtable would.
  mattr_accessor :stubbed

  # A table in memory: records by ID, each upsert or update merged into them, and every call kept in order.
  class Stub
    attr_reader :records, :calls

    def initialize
      @records = {}
      @calls = []
    end

    def upsert(fields, merge_on)
      @calls << [ :upsert, fields ]
      id = "rec#{Digest::SHA256.hexdigest(fields[merge_on].to_s).first(14)}"
      { "id" => id, "fields" => (@records[id] = (@records[id] || {}).merge(fields).compact) }
    end

    def update(id, fields)
      @calls << [ :update, fields ]
      { "id" => id, "fields" => (@records[id] = @records.fetch(id).merge(fields).compact) }
    end

    def upserts = @calls.count { |kind, _| kind == :upsert }
  end

  def self.configured?
    !stubbed.nil? || Rails.configuration.x.airtable_api_key.present?
  end

  # Adds the record, or updates the one with the same value in merge_on. The record as Airtable has it now:
  # { "id" =>, "fields" => } (Airtable leaves out fields that are empty).
  def self.upsert(fields, merge_on:)
    return stubbed.upsert(fields, merge_on) if stubbed

    body = { performUpsert: { fieldsToMergeOn: [ merge_on ] }, typecast: true, records: [ { fields: } ] }
    patch(body).dig("records", 0) or raise Unavailable, "Airtable sent no record back"
  end

  # Changes these fields on the record with this ID. The record as Airtable has it now.
  def self.update(id, fields)
    return stubbed.update(id, fields) if stubbed

    patch({ typecast: true, records: [ { id:, fields: } ] }).dig("records", 0) or raise Unavailable, "Airtable sent no record back"
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
