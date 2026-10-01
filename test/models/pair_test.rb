require "test_helper"

class PairTest < ActiveSupport::TestCase
  test "two projects pair once, and each is the other's buddy" do
    pair = projects(:orpheus).pair_with(projects(:ana))

    assert pair.persisted?
    assert_equal projects(:ana), projects(:orpheus).reload.buddy
    assert_equal projects(:orpheus), projects(:ana).reload.buddy
    assert projects(:orpheus).step_done?("buddy")
    assert_not projects(:orpheus).step_open?("buddy")

    again = projects(:ana).pair_with(projects(:orpheus))
    assert_not again.persisted?
    assert_equal [ "One of you already has a buddy" ], again.errors.full_messages
  end

  test "you can't pair with yourself" do
    assert_equal [ "You can't pair with yourself" ], projects(:ana).pair_with(projects(:ana)).errors.full_messages
  end

  test "an invite code is your first name, made unique" do
    assert_equal "ana", projects(:ana).buddy_code!
    assert_equal "orpheus", projects(:orpheus).buddy_code!

    other = users(:ana).dup.tap { |user| user.update!(hca_id: "ident!ana2") }
    taken = projects(:ana).dup.tap { |project| project.update!(user: other, buddy_code: nil) }
    assert_match(/\Aana-[a-z0-9]{4}\z/, taken.buddy_code!)
  end
end
