ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# Signing in with Hack Club Auth goes straight to the callback with this user instead of leaving the app, and
# nothing asks the real Hack Club Auth who's there.
OmniAuth.config.test_mode = true
Rails.application.config.x.hack_club_auth_whoami_url = nil

# Nobody asks the real Hackatime either: who each token belongs to, the projects each Hackatime user has
# logged time on, and when they were building (none of the time, unless a test says otherwise).
Hackatime.stubbed_users = { "token-orpheus" => "1001", "token-heidi" => "1002" }
Hackatime.stubbed_projects = {
  "1001" => [ Hackatime::Project.new("rhythm-game", 5400), Hackatime::Project.new("beat-sheet-art", 900),
              Hackatime::Project.new("dotfiles", 11_160) ],
  "1002" => [ Hackatime::Project.new("heidis-game", 600) ]
}
Hackatime.stubbed_spans = {}
# What Hackatime makes of each of them, by Hackatime user ID: nothing it's said, unless a test says otherwise.
Hackatime.stubbed_trust = {}

# Nor GitHub (no repo is there, unless a test says so) or anyone's demo link (each answers 200, unless a test says).
Github.stubbed = {}
DemoProbe.stubbed = {}
# Nor Lapse, which counts as set up here (stubbing it is what that means in tests): nobody has a recording, unless a
# test says so. A test can set it to nil for a wrong tool with no Lapse program key at all.
Lapse.stubbed = {}

module HackClubAuthHelpers
  def mock_hack_club_auth(uid: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi",
                          slack_id: "U0HEIDI", verification_status: "verified", ysws_eligible: true, address: HQ_ADDRESS,
                          phone_number: "+18025550123", birthdate: "2010-04-01")
    OmniAuth.config.mock_auth[:hackclub] = OmniAuth::AuthHash.new(
      provider: "hackclub", uid:,
      info: { email:, name:, first_name: },
      extra: { raw_info: { sub: uid, email:, name:, slack_id:, verification_status:, ysws_eligible:, address:, phone_number:, birthdate: }.compact }
    )
  end

  HQ_ADDRESS = { "street_address" => "15 Falls Rd", "locality" => "Shelburne", "region" => "VT", "postal_code" => "05482",
                 "country" => "US" }.freeze
end

module HackatimeHelpers
  # Linking Hackatime goes straight to the callback with this token.
  def mock_hackatime(token: "token-orpheus")
    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", uid: nil, credentials: { token: })
  end

  # As if they'd already linked Hackatime.
  def link_hackatime(user, token: "token-#{user.first_name.downcase}")
    user.update!(hackatime_uid: Hackatime.stubbed_users.fetch(token), hackatime_access_token: token)
  end

  # As if Hackatime answered about their hours but not about what it makes of them.
  def with_hackatime_trust_down
    Hackatime.singleton_class.alias_method(:trust_without_test, :trust)
    Hackatime.define_singleton_method(:trust) { |*| raise Hackatime::Unavailable, "timed out" }
    yield
  ensure
    Hackatime.singleton_class.alias_method(:trust, :trust_without_test)
    Hackatime.singleton_class.remove_method(:trust_without_test)
  end

  # A span of `minutes` starting at `at`, as Hackatime sends it.
  def hackatime_span(at, minutes)
    { "start_time" => at.to_f, "end_time" => (at + minutes.minutes).to_f, "duration" => minutes * 60 }
  end

  # What Hackatime says Orpheus built, for the block: `hours` of it, on wrong tool's first day (so every number of
  # hours has it). The block runs on the day after, so that day's over whatever the time is now.
  def with_hackatime_hours(hours, uid: "1001")
    before = Hackatime.stubbed_spans
    Hackatime.stubbed_spans = before.merge(uid => [ hackatime_span(Time.utc(2026, 10, 6, 15), (hours * 60).round) ])
    travel_to(Time.utc(2026, 10, 7, 12)) { yield }
  ensure
    Hackatime.stubbed_spans = before
  end
end

module LapseHelpers
  # A timelapse as Lapse would hand it over, for Lapse.stubbed.
  def lapse_timelapse(id:, hackatime_project:, name: "Building it", seconds: 42, recorded_at: Time.utc(2026, 10, 8, 20),
                      visibility: "UNLISTED")
    Lapse::Timelapse.new(id:, name:, hackatime_project:, page_url: "https://lapse.hackclub.com/timelapse/#{id}",
                         playback_url: "https://lapse.hackclub.com/video/#{id}.mp4", thumbnail_url: nil, seconds:,
                         recorded_at:, visibility:)
  end

  # As if the real Lapse were there, with a program key, answering these paths: a hash is the JSON it sends back, an
  # integer just that status. Collects what it was asked with, in `lapse_asked`.
  def with_lapse_answering(answers, key: "pk_lapse_test")
    was = [ Lapse.stubbed, Rails.configuration.x.lapse_program_key ]
    Lapse.stubbed = nil
    Rails.configuration.x.lapse_program_key = key
    asked = lapse_asked.clear
    http = Object.new
    http.define_singleton_method(:get) do |path, headers = {}|
      asked << [ path, headers["Authorization"] ]
      answer = answers.fetch(path) { raise "Lapse wasn't expecting #{path}" }
      status, body = answer.is_a?(Integer) ? [ answer, "" ] : [ 200, answer.to_json ]
      Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "").tap do |response|
        response.instance_variable_set(:@body, body)
        response.instance_variable_set(:@read, true)
      end
    end
    Net::HTTP.singleton_class.alias_method(:start_without_test, :start)
    Net::HTTP.define_singleton_method(:start) { |*, **, &block| block.call(http) }
    Rails.cache.clear # the Lapse user each email belongs to is cached
    yield
  ensure
    Net::HTTP.singleton_class.alias_method(:start, :start_without_test)
    Net::HTTP.singleton_class.remove_method(:start_without_test)
    Lapse.stubbed, Rails.configuration.x.lapse_program_key = was
    Rails.cache.clear
  end

  def lapse_asked
    @lapse_asked ||= []
  end

  # As if Lapse were set up here but not answering.
  def with_lapse_down
    Lapse.singleton_class.alias_method(:timelapses_without_test, :timelapses)
    Lapse.define_singleton_method(:timelapses) { |*| raise Lapse::Unavailable, "timed out" }
    yield
  ensure
    Lapse.singleton_class.alias_method(:timelapses, :timelapses_without_test)
    Lapse.singleton_class.remove_method(:timelapses_without_test)
  end
end

module ShopHelpers
  # As if every pick took this many hours (Shop.hours_for), for the schedule tests, whose arithmetic is about days,
  # not prices.
  def with_hours_needed(hours)
    Shop.singleton_class.alias_method(:hours_for_without_test, :hours_for)
    Shop.define_singleton_method(:hours_for) { |_dollars| hours }
    yield
  ensure
    Shop.singleton_class.alias_method(:hours_for, :hours_for_without_test)
    Shop.singleton_class.remove_method(:hours_for_without_test)
  end
end

ActiveSupport::TestCase.include ShopHelpers
ActiveSupport::TestCase.include HackClubAuthHelpers
ActiveSupport::TestCase.include HackatimeHelpers
ActiveSupport::TestCase.include LapseHelpers
