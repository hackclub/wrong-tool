# A nudge as a Slack message (Block Kit): what Clippy says with him acting out his mood beside it, how he feels
# underneath, then the button and a way to stop these. Both buttons are tracked links (see NudgeLinksController).
class Nudge::Message
  attr_reader :nudge

  def initialize(nudge)
    @nudge = nudge
  end

  def blocks
    [
      { type: "section", text: { type: "mrkdwn", text: nudge.text },
        accessory: { type: "image", image_url: Nudge::Copy.image_url(nudge.mood), alt_text: "clippy, #{nudge.mood}" } },
      ({ type: "context", elements: [ { type: "mrkdwn", text: nudge.mood_text } ] } if nudge.mood_text.present?),
      { type: "actions", elements: [
        { type: "button", text: { type: "plain_text", text: Nudge::Copy.link_for(nudge.arm).first }, style: "primary",
          url: nudge.link_url, action_id: "nudge_open" },
        { type: "button", text: { type: "plain_text", text: Nudge::Copy::SLACK_MUTE }, url: nudge.stop_url, action_id: "nudge_stop" }
      ] }
    ].compact
  end
end
