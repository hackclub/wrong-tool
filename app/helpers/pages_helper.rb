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

  def program_dates
    Date.new(2026, 10, 2)..Date.new(2026, 10, 16)
  end

  # "oct 2", as the dates read on the sheet.
  def sheet_date(date)
    date.strftime("%b %-d").downcase
  end

  # DATE(2026,10,2), for building formulas.
  def date_formula(date)
    "DATE(#{date.year},#{date.month},#{date.day})"
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
