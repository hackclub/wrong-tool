require "test_helper"

class NudgeMessageTest < ActiveSupport::TestCase
  test "says it plainly with Clippy acting out his mood, how he feels, and two tracked buttons" do
    nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "progress", mood: "proud",
                                           text: "you're 35% of the way to a miyoo mini plus.", mood_text: "📎 clippy is quietly proud.")
    section, context, actions = Nudge::Message.new(nudge).blocks

    assert_equal nudge.text, section.dig(:text, :text)
    assert_equal "#{Rails.configuration.x.app_url}/clippy/proud.gif", section.dig(:accessory, :image_url)
    assert Rails.root.join("public/clippy/proud.gif").exist?
    assert_equal "📎 clippy is quietly proud.", context.dig(:elements, 0, :text)
    assert_equal [ "see your progress", "stop these messages" ], actions[:elements].map { |button| button.dig(:text, :text) }
    assert_equal [ "#{Rails.configuration.x.app_url}/n/#{nudge.token}", "#{Rails.configuration.x.app_url}/n/#{nudge.token}/stop" ],
                 actions[:elements].map { |button| button[:url] }
  end

  test "dramatic Clippy is all mood, so there's no line about how he feels" do
    nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "dramatic", mood: "dramatic", text: "clippy is fine.")
    assert_equal %w[section actions], Nudge::Message.new(nudge).blocks.map { |block| block[:type] }
  end

  test "every mood has a picture of Clippy" do
    (Nudge::Copy::MOOD_FOR.values.uniq + [ "dramatic" ]).each do |mood|
      assert Rails.root.join("public/clippy/#{mood}.gif").exist?, "public/clippy/#{mood}.gif"
    end
  end
end
