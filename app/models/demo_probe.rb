require "net/http"
require "resolv"

# Whether a ship's demo link opens (ShipEvidence): the status it answers with, after up to MAX_REDIRECTS redirects.
# Asking for a login (401, 403) or slowing us down (429) still counts as there. It never asks anything on a private
# network: every host has to resolve to public addresses only, and the request goes to the address that was checked.
module DemoProbe
  MAX_REDIRECTS = 3
  # Addresses that aren't the public internet, past what IPAddr knows (private, loopback, link-local).
  BLOCKED = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 64:ff9b::/96].map { |range| IPAddr.new(range) }

  Result = Data.define(:status, :error) do
    def reachable? = status.present? && (status < 400 || [ 401, 403, 429 ].include?(status))
  end

  # Tests set this instead of asking the internet: { url => status, or an error message }. Anything else is a 200.
  mattr_accessor :stubbed

  def self.check(url)
    if stubbed
      answer = stubbed.fetch(url, 200)
      return answer.is_a?(Integer) ? Result.new(status: answer, error: nil) : Result.new(status: nil, error: answer)
    end

    uri = URI.parse(url)
    (MAX_REDIRECTS + 1).times do
      raise ArgumentError, "isn't a web link" unless %w[http https].include?(uri.scheme) && uri.host.present?

      response = request(uri)
      return Result.new(status: response.code.to_i, error: nil) unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = uri.merge(response["location"])
    end
    Result.new(status: nil, error: "redirects more than #{MAX_REDIRECTS} times")
  rescue ArgumentError, URI::InvalidURIError, Resolv::ResolvError => error
    Result.new(status: nil, error: error.message)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => error
    Result.new(status: nil, error: "didn't answer (#{error.class.name.demodulize})")
  end

  def self.request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = public_address(uri.host)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 8
    http.start { http.request_get(uri.request_uri, "User-Agent" => "wrong-tool-review") { |response| return response } }
  end

  def self.public_address(host)
    addresses = Resolv.getaddresses(host).map { |address| IPAddr.new(address) }
    raise ArgumentError, "doesn't resolve" if addresses.empty?
    raise ArgumentError, "points at a private network" if addresses.any? { |address| blocked?(address) }

    addresses.first.to_s
  end

  def self.blocked?(address)
    address = address.native if address.ipv4_mapped?
    address.private? || address.loopback? || address.link_local? || BLOCKED.any? { |range| range.family == address.family && range.include?(address) }
  end
  private_class_method :request, :public_address, :blocked?
end
