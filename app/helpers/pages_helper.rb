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

  def organizer_url
    "https://cskartikey.dev/"
  end

  def footer_links
    {
      "slack" => "https://hackclub.com/slack/",
      "clubs" => "https://hackclub.com/clubs/",
      "privacy" => "https://hackclub.com/privacy-and-terms",
      "fulfillment" => "https://forms.hackclub.com/bounty"
    }
  end
end
