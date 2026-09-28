module PagesHelper
  # Each section of the landing page is a sheet; the sheet tabs are the navigation.
  def section_names
    [ "Hero", "How it works", "Ideas", "Rules", "Reward", "Gallery", "FAQ" ]
  end

  def reward_name
    "RG35XX Pro"
  end

  def hours_per_reward
    10
  end
end
