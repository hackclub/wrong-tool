require "test_helper"

class NudgeMessageTest < ActiveSupport::TestCase
  test "Clippy acting out his mood up top, then what he says with how he feels quoted under it, and two tracked buttons" do
    nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "progress", mood: "proud",
                                           text: "you're 35% of the way to a miyoo mini plus.", mood_text: ":clippy-proud: clippy is quietly proud. :blob-yay:")
    image, section, actions = Nudge::Message.new(nudge).blocks

    assert_equal "#{Rails.configuration.x.app_url}/clippy/proud.gif", image[:image_url]
    assert Rails.root.join("public/clippy/proud.gif").exist?
    assert_equal "you're 35% of the way to a miyoo mini plus.\n>:clippy-proud: clippy is quietly proud. :blob-yay:", section.dig(:text, :text)
    assert_equal [ "see your progress", "stop these messages" ], actions[:elements].map { |button| button.dig(:text, :text) }
    assert_equal [ "#{Rails.configuration.x.app_url}/n/#{nudge.token}", "#{Rails.configuration.x.app_url}/n/#{nudge.token}/stop" ],
                 actions[:elements].map { |button| button[:url] }
  end

  test "dramatic Clippy is all mood, so there's no line about how he feels" do
    nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "dramatic", mood: "dramatic", text: "clippy is fine.")
    assert_equal "clippy is fine.", Nudge::Message.new(nudge).blocks[1].dig(:text, :text)
  end

  test "every mood has a picture of Clippy" do
    (Nudge::Copy::MOOD_FOR.values.uniq + [ "dramatic" ]).each do |mood|
      assert Rails.root.join("public/clippy/#{mood}.gif").exist?, "public/clippy/#{mood}.gif"
    end
  end
end
