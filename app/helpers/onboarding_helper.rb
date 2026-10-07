module OnboardingHelper
  # The four questions, one per cell down column A.
  def onboarding_steps
    [
      { label: "Platform", question: "Pick your platform.",
        help: "Anything not built for games. You can switch later." },
      { label: "Project", question: "What are you building?",
        help: "You can switch it later. Just start something for now :)" },
      { label: "Prize", question: "Pick your prize.",
        help: "Pick one. It ships once you log #{hours_per_reward} hours. (You can get more!)" },
      { label: "Commit", question: "Set your pace.",
        help: "Pick a pace and a time, then sign your pledge." }
    ]
  end

  # Each wrong tool, and the endings the idea slot machine rolls for it.
  def onboarding_tools
    [
      { id: "spreadsheet", name: "Spreadsheet", extension: ".xlsx",
        phrases: [ "in Google Sheets", "in an Excel workbook", "drawn with conditional formatting", "where every cell is a pixel",
                   "that runs on checkboxes", "powered by iterative calc" ] },
      { id: "figma", name: "Figma", extension: ".fig",
        phrases: [ "in Figma prototypes", "where frames are rooms", "run on Figma variables", "played in Present mode" ] },
      { id: "email", name: "Email", extension: ".eml",
        phrases: [ "played over email", "where every reply is a turn", "run by inbox filters", "in your drafts folder" ] },
      { id: "ssh", name: "SSH", extension: ".sh",
        phrases: [ "over SSH", "in a login shell", "hiding in .bash_profile", "for a bare terminal" ] },
      { id: "shaders", name: "Shaders", extension: ".glsl",
        phrases: [ "in one fragment shader", "where state is pixels", "in a single GLSL file", "running only on the GPU" ] },
      { id: "other", name: "Other", extension: ".???", phrases: [] }
    ].map { |tool| tool.merge(preposition: Project.preposition_for(tool[:id])) }
  end

  # A4's answers: minutes a day (with how the chip reads), and when you usually build (with when Clippy checks in).
  def onboarding_paces
    [ [ 20, "20 min" ], [ 45, "45 min" ], [ 60, "1 hr" ], [ 120, "2 hrs" ], [ 180, "3 hrs" ] ]
  end

  def onboarding_build_times
    [ [ "after school", "after school" ], [ "evening", "every evening" ], [ "late night", "late at night" ],
      [ "weekends", "on weekends" ] ]
  end

  def onboarding_genres
    [ "dungeon crawler", "platformer", "roguelike", "rhythm game", "tower defense", "farming sim", "racing game",
      "text adventure", "puzzle game", "idle clicker", "pet simulator", "bullet hell", "murder mystery", "fishing game",
      "card battler", "escape room", "snake clone", "heist game", "dating sim", "golf game" ]
  end

  # The third reel: a twist that follows any genre ("a snake clone where the floor is lava") and reads before the
  # tool ("... in Spreadsheet"). Kept to 31 characters so the longest fits a phone-width reel.
  def onboarding_twists
    [ "where you play the villain", "set in a haunted laundromat", "about a very tired wizard", "with only one button",
      "where gravity flips every turn", "starring a sentient toaster", "set entirely underwater", "where you can't see yourself",
      "that plays itself when you stop", "set in a dentist's waiting room", "with a goose that steals things", "set on a moving train",
      "where time runs backwards", "about tax season", "where the enemies are polite", "with a disappointed narrator",
      "set during a thunderstorm", "where you're the final boss", "where the floor is lava", "about a cat who's late for work",
      "set inside a vending machine", "where dying makes you stronger", "with a tutorial that lies", "set in a library after hours",
      "where everything is on fire", "about escaping a group chat", "starring a haunted pencil", "where the map keeps shrinking",
      "set at the end of a school day", "where your shadow plays too", "about a snail with places to be", "where the music is the enemy",
      "set on a giant pizza", "where you only move backwards", "about a ghost learning to cook", "where the sun never comes up",
      "with one life and no restarts", "where every level is a lie", "set in a submarine with a leak", "about a very small knight" ]
  end

  # Every idea the reels can land on, as the pledge stores it: "a snake clone where the floor is lava".
  def onboarding_rolled_ideas
    onboarding_genres.product(onboarding_twists).map { |genre, twist| "#{article_for(genre)} #{genre} #{twist}" }
  end

  # Rolled ideas someone's already pledged (in any tool), and how many times. The roller steers clear of ones pledged
  # twice, so at most two people end up building the same thing.
  def onboarding_taken_ideas
    Project.where(idea: onboarding_rolled_ideas).group(:idea).count
  end

  def article_for(noun)
    noun.match?(/\A[aeiou]/i) ? "an" : "a"
  end

  def onboarding_prizes
    [
      { id: "rg35xx", maker: "ANBERNIC", name: "RG35XX Pro", full: "ANBERNIC RG35XX Pro",
        image: "rewards/rg35xx-pro.webp", alt: "ANBERNIC RG35XX Pro handheld in transparent teal" },
      { id: "miyoo", maker: "MIYOO", name: "Mini Plus", full: "Miyoo Mini Plus",
        image: "rewards/miyoo-mini-plus.webp", alt: "Miyoo Mini Plus handheld in grey, front and back" }
    ]
  end
end
