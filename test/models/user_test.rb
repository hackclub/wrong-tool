require "test_helper"

class UserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "signing in for the first time makes a user from Hack Club Auth's claims" do
    user = User.from_omniauth(mock_hack_club_auth)

    assert_equal "ident!heidi", user.hca_id
    assert_equal "heidi@hackclub.com", user.email
    assert_equal "Heidi Hakkuun", user.name
    assert_equal "Heidi", user.first_name
    assert_equal "U0HEIDI", user.slack_id
    assert_equal "verified", user.verification_status
    assert user.ysws_eligible
  end

  test "signing in again finds the same user and refreshes what changed" do
    user = users(:orpheus)
    assert_no_difference -> { User.count } do
      User.from_omniauth(mock_hack_club_auth(uid: user.hca_id, name: "Orpheus Hacksworth", ysws_eligible: false))
    end

    user.reload
    assert_equal "Orpheus Hacksworth", user.name
    assert_not user.ysws_eligible
  end

  test "everyone's picture is an animal on a colour, the same every time" do
    orpheus = users(:orpheus)
    assert_includes User::ANIMALS, orpheus.animal
    assert_includes User::AVATAR_COLORS, orpheus.avatar_color
    assert_equal [ orpheus.animal, orpheus.avatar_color ], User.find(orpheus.id).then { |again| [ again.animal, again.avatar_color ] }
    assert Rails.root.join("app/assets/images/animals/#{orpheus.animal}.svg").exist?

    pictures = 200.times.map { |index| User.new(hca_id: "ident!#{index}").then { |user| [ user.animal, user.avatar_color ] } }
    assert_operator pictures.uniq.size, :>, 100, "people mostly get different ones"
  end

  test "your timezone is remembered from your browser, if it's a real one" do
    user = users(:ana)
    user.remember_timezone("America/New_York")
    assert_equal "America/New_York", user.reload.timezone

    user.remember_timezone("Not/A_Zone")
    user.remember_timezone("")
    assert_equal "America/New_York", user.reload.timezone
  end

  test "a new timezone counts your streak days again" do
    user = users(:orpheus)
    link_hackatime(user)
    user.project.update!(hackatime_projects: [ "rhythm-game" ])

    assert_enqueued_with(job: StreakSyncJob, args: [ user.id ]) { user.remember_timezone("Asia/Kolkata") }
    assert_no_enqueued_jobs(only: StreakSyncJob) { user.remember_timezone("Asia/Kolkata") }
  end

  test "everyone else sees your Slack display name, or your animal without one, never your real name" do
    user = users(:ana)
    assert_equal "pixelana", user.public_name

    user.update!(slack_display_name: nil)
    assert_equal "Anonymous #{user.animal.capitalize}", user.public_name
    assert_no_match(/Ana|Lovelace/, user.public_name)
  end
end
