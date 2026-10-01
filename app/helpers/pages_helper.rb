module PagesHelper
  # Each section of the landing page is a sheet; the sheet tabs are the navigation.
  def section_names
    [ "Hero", "How it works", "Ideas", "Examples", "FAQ" ]
  end

  def hours_per_reward
    Program::HOURS_PER_REWARD
  end

  def program_dates
    Program::DATES
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

  # The original flap, played in Google Sheets.
  def flap_url
    "https://cskartikey.dev/flap"
  end

  def hackatime_url
    "https://hackatime.hackclub.com/"
  end

  def lapse_url
    "https://lapse.hackclub.com/"
  end

  # What the idea roulette on the Ideas sheet spins through.
  def idea_genres
    [ "platformer", "rhythm game", "roguelike", "dating sim", "tower defense", "racing game",
      "puzzle game", "idle clicker", "text adventure", "fishing game", "bullet hell", "card game" ]
  end

  def idea_platforms
    [ "google sheets", "figma", "google slides", "google forms", "powerpoint", "excel",
      "pure css", "a pdf", "notion", "your inbox", "a terminal", "git commits" ]
  end

  def footer_credit
    "Made with ♥ by teenagers, for teenagers at Hack Club — a 501(c)(3) nonprofit and a network of 100k+ technical high schoolers."
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
