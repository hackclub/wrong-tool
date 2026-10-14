require "test_helper"

class SlackEmojiTest < ActiveSupport::TestCase
  test "Clippy's own emotes are his gifs here, the ones the site says are kept here too, Slack's come from its list, and a stranger is nothing" do
    assert_equal "/clippy/proud.gif", SlackEmoji.url("clippy-proud")
    assert_equal "/emotes/yay.gif", SlackEmoji.url("yay")
    assert_equal "/emotes/heavysob.png", SlackEmoji.url("heavysob")
    assert_equal "/emotes/dino-bbq.gif", SlackEmoji.url("dino-bbq"), "Slack's alias, as its own picture here"
    assert_nil SlackEmoji.url("blob-cheer"), "Slack isn't configured in tests, so there's no list"

    SlackEmoji.stubbed = { "blob-cheer" => "https://emoji.slack-edge.com/T0266FRGM/blob-cheer/abc.png" }
    assert_equal "https://emoji.slack-edge.com/T0266FRGM/blob-cheer/abc.png", SlackEmoji.url("blob-cheer")
    assert_equal "/emotes/yay.gif", SlackEmoji.url("yay"), "the copy kept here comes first"
    assert_nil SlackEmoji.url("not-an-emote")
  ensure
    SlackEmoji.stubbed = nil
  end

  test "every emote the site's own lines use is kept here" do
    said = Dir["app/models/nudge/*.rb", "app/helpers/shop_helper.rb", "app/javascript/controllers/shop_controller.js", "app/models/reward_notifier.rb",
                "app/models/extension_notifier.rb", "app/models/seller_request_notifier.rb", "app/models/order_notifier.rb"]
             .flat_map { |file| File.read(file).scan(/:([a-z0-9_+-]+):/).flatten }.uniq.reject { |name| name.match?(SlackEmoji::CLIPPY) }
    assert_empty said - SlackEmoji::BUNDLED.keys, "save these from Slack into public/emotes"
  end
end
