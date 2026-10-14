module ApplicationHelper
  # Someone's picture: their animal on their colour (see User#animal), with what everyone sees them as (never their
  # real name) for screen readers and on hover.
  def avatar_tag(user, class_name = nil, **options)
    name = user.public_name
    attributes = { class: [ "avatar", class_name ], style: "--avatar-color: #{user.avatar_color}", role: "img",
                   aria: { label: name }, title: name }
    tag.span(**attributes.merge(options)) do
      inline_svg_tag("animals/#{user.animal}.svg", aria_hidden: true)
    end
  end

  # A line with Slack emotes in it (":clippy-proud: clippy is quietly proud. :blob-yay:"), the emotes as the pictures
  # Slack shows (SlackEmoji). One nobody knows stays as its name.
  def emotes(text)
    safe_join(text.to_s.split(/(:[a-z0-9_+-]+:)/i).map do |part|
      name = part[/\A:([a-z0-9_+-]+):\z/i, 1]
      url = name && SlackEmoji.url(name)
      url ? image_tag(url, alt: part, title: name, class: "emote") : part
    end)
  end

  # Clippy: one frame of his sprite sheet, which mascot/clippy.js moves through.
  def clippy_sprite_tag(class_name = nil, data: {})
    tag.span(class: [ "onboarding-mascot__sprite", class_name ], aria: { hidden: true }, data:,
             style: "background-image: url(#{image_path("mascot/clippy.webp")})")
  end
end
