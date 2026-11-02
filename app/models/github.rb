require "net/http"

# GitHub's REST API, read-only, for reviewing a ship (ShipEvidence): a public repo's details, its commits between two
# times, and whether it has a README. A repo that isn't there (or isn't public) is nil.
module Github
  Repo = Data.define(:full_name, :created_at, :pushed_at, :fork, :parent, :stars)
  Commit = Data.define(:sha, :message, :author_name, :author_login, :at, :url)
  MAX_COMMITS = 300

  # GitHub couldn't be reached, ran out of requests, or answered something we can't use.
  class Unavailable < StandardError; end

  # Tests set this instead of asking the real GitHub: { "owner/name" => { repo: Repo, commits: [ Commit ], readme: true } }.
  # A repo not in it isn't there.
  mattr_accessor :stubbed

  # "owner/name" for a github.com repo link (a tree, blob or .git link too), or nil for anything else.
  def self.repo_name(url)
    uri = URI.parse(url.to_s.strip)
    return unless uri.host&.downcase&.delete_prefix("www.") == "github.com"

    owner, name = uri.path.split("/").compact_blank
    "#{owner}/#{name.delete_suffix(".git")}" if owner && name
  rescue URI::InvalidURIError
    nil
  end

  def self.repo(name)
    return stubbed.dig(name, :repo) if stubbed

    response = get("/repos/#{name}")
    return if response.is_a?(Net::HTTPNotFound)

    body = parse(response)
    Repo.new(full_name: body["full_name"], created_at: Time.zone.parse(body["created_at"]), pushed_at: body["pushed_at"] && Time.zone.parse(body["pushed_at"]),
             fork: body["fork"], parent: body.dig("parent", "full_name"), stars: body["stargazers_count"].to_i)
  end

  # Newest first, up to MAX_COMMITS.
  def self.commits(name, since:, until_time:)
    return stubbed.dig(name, :commits).to_a.select { |commit| commit.at.between?(since, until_time) } if stubbed

    commits = []
    (1..(MAX_COMMITS / 100)).each do |page|
      query = { since: since.utc.iso8601, until: until_time.utc.iso8601, per_page: 100, page: }.to_query
      response = get("/repos/#{name}/commits?#{query}")
      return commits if response.is_a?(Net::HTTPNotFound) || response.is_a?(Net::HTTPConflict) # gone, or empty

      batch = parse(response)
      commits += batch.map do |commit|
        Commit.new(sha: commit["sha"], message: commit.dig("commit", "message").to_s.lines.first.to_s.strip,
                   author_name: commit.dig("commit", "author", "name"), author_login: commit.dig("author", "login"),
                   at: Time.zone.parse(commit.dig("commit", "author", "date")), url: commit["html_url"])
      end
      break if batch.size < 100
    end
    commits
  end

  def self.readme?(name)
    return stubbed.dig(name, :readme).present? if stubbed

    get("/repos/#{name}/readme").is_a?(Net::HTTPSuccess)
  end

  def self.get(path)
    uri = URI("https://api.github.com#{path}")
    headers = { "Accept" => "application/vnd.github+json", "User-Agent" => "wrong-tool-review" }
    headers["Authorization"] = "Bearer #{Rails.configuration.x.github_token}" if Rails.configuration.x.github_token.present?
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.get(uri.request_uri, headers) }
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => error
    raise Unavailable, error.message
  end

  def self.parse(response)
    raise Unavailable, "GitHub answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => error
    raise Unavailable, error.message
  end
  private_class_method :get, :parse
end
