# A nudge as a Slack message (Block Kit): Clippy acting out his mood, big, up top; what he says with how he feels
# quoted under it; then the button and a way to stop these. Both buttons are tracked links (see
# NudgeLinksController).
class Nudge::Message
  attr_reader :nudge

  def initialize(nudge)
    @nudge = nudge
  end

  def blocks
    [
      { type: "image", image_url: Nudge::Copy.image_url(nudge.mood), alt_text: "clippy, #{nudge.mood}" },
      { type: "section", text: { type: "mrkdwn", text: text } },
      { type: "actions", elements: [
        { type: "button", text: { type: "plain_text", text: Nudge::Copy.link_for(nudge.arm).first }, style: "primary",
          url: nudge.link_url, action_id: "nudge_open" },
        { type: "button", text: { type: "plain_text", text: Nudge::Copy::SLACK_MUTE }, url: nudge.stop_url, action_id: "nudge_stop" }
      ] }
    ]
  end

  # The message, and how Clippy feels about it as a quote (nothing for dramatic, which is all mood).
  def text
    nudge.mood_text.present? ? "#{nudge.text}\n>#{nudge.mood_text}" : nudge.text
  end
end
