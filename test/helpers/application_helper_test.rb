require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "emotes in a line become the pictures Slack shows, and one nobody knows stays as its name" do
    SlackEmoji.stubbed = { "blob-cheer" => "https://emoji.slack-edge.com/T0266FRGM/blob-cheer/abc.png" }
    html = emotes(":clippy-proud: clippy is quietly proud. :yay: :blob-cheer: :mystery:")
    expected = '<img class="emote" title="clippy-proud" alt=":clippy-proud:" src="/clippy/proud.gif"> clippy is quietly proud. ' \
               '<img class="emote" title="yay" alt=":yay:" src="/emotes/yay.gif"> ' \
               '<img class="emote" title="blob-cheer" alt=":blob-cheer:" src="https://emoji.slack-edge.com/T0266FRGM/blob-cheer/abc.png"> :mystery:'
    assert_dom_equal expected, html
    assert_equal "", emotes(nil)
  ensure
    SlackEmoji.stubbed = nil
  end
end
