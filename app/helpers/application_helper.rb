module ApplicationHelper
  # Someone's picture: their animal on their colour (see User#animal), with their name for screen readers and on hover.
  def avatar_tag(user, class_name = nil, **options)
    name = user.first_name.presence || user.name
    attributes = { class: [ "avatar", class_name ], style: "--avatar-color: #{user.avatar_color}", role: "img",
                   aria: { label: name }, title: "#{name} the #{user.animal}" }
    tag.span(**attributes.merge(options)) do
      inline_svg_tag("animals/#{user.animal}.svg", aria_hidden: true)
    end
  end

  # Clippy: one frame of his sprite sheet, which mascot/clippy.js moves through.
  def clippy_sprite_tag(class_name = nil, data: {})
    tag.span(class: [ "onboarding-mascot__sprite", class_name ], aria: { hidden: true }, data:,
             style: "background-image: url(#{image_path("mascot/clippy.webp")})")
  end
end
