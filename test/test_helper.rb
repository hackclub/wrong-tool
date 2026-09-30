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

# Signing in with Hack Club Auth goes straight to the callback with this user instead of leaving the app.
OmniAuth.config.test_mode = true

module HackClubAuthHelpers
  def mock_hack_club_auth(uid: "ident!heidi", email: "heidi@hackclub.com", name: "Heidi", slack_id: "U0HEIDI",
                          verification_status: "verified", ysws_eligible: true)
    OmniAuth.config.mock_auth[:hackclub] = OmniAuth::AuthHash.new(
      provider: "hackclub", uid:,
      info: { email:, name: },
      extra: { raw_info: { sub: uid, email:, name:, slack_id:, verification_status:, ysws_eligible: } }
    )
  end
end

ActiveSupport::TestCase.include HackClubAuthHelpers
