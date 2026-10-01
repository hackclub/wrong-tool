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

# Nobody asks the real Hackatime either: these are the projects each Slack ID has logged time on.
Hackatime.stubbed_projects = {
  "U0ORPHEUS" => [ Hackatime::Project.new("rhythm-game", 5400), Hackatime::Project.new("beat-sheet-art", 900),
                   Hackatime::Project.new("dotfiles", 11_160) ],
  "U0HEIDI" => [ Hackatime::Project.new("heidis-game", 600) ]
}

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

ActiveSupport::TestCase.include HackClubAuthHelpers
