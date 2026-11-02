module GalleryHelper
  # The picture on a ship's card: its own screenshot, or the project's if the ship's is missing (an older ship, or a
  # file that's gone). Nil with neither.
  def gallery_screenshot(ship)
    [ ship.screenshot, ship.project.screenshot ].find { |shot| shot.attached? && shot.blob&.persisted? }
  end
end
