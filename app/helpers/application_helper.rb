module ApplicationHelper
  # Clippy: one frame of his sprite sheet, which mascot/clippy.js moves through.
  def clippy_sprite_tag(class_name = nil, data: {})
    tag.span(class: [ "onboarding-mascot__sprite", class_name ], aria: { hidden: true }, data:,
             style: "background-image: url(#{image_path("mascot/clippy.webp")})")
  end
end
