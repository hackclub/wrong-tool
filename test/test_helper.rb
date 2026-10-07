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

module HackClubAuthHelpers
  def mock_hack_club_auth(uid: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi Hakkuun", first_name: "Heidi",
                          slack_id: "U0HEIDI", verification_status: "verified", ysws_eligible: true)
    OmniAuth.config.mock_auth[:hackclub] = OmniAuth::AuthHash.new(
      provider: "hackclub", uid:,
      info: { email:, name:, first_name: },
      extra: { raw_info: { sub: uid, email:, name:, slack_id:, verification_status:, ysws_eligible: } }
    )
  end
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

ActiveSupport::TestCase.include HackClubAuthHelpers
ActiveSupport::TestCase.include HackatimeHelpers
