module OnboardingHelper
  # The four questions, one per cell down column A.
  def onboarding_steps
    [
      { label: "Platform", question: "Pick your platform.",
        help: "Anything not made for making games counts. Game engines don't. You can switch later." },
      { label: "Project", question: "What are you building?",
        help: "You can switch it later. Just start something for now :)" },
      { label: "Prize", question: "Pick your handheld.",
        help: "Each takes about the hours it says. Pick the one you'd play; colours, extras and changing your mind come later." },
      { label: "Commit", question: "Set your pace.",
        help: "Pick a pace and a time, then sign your pledge." }
    ]
  end

  # Each wrong tool, the endings the idea slot machine rolls for it, and how its hours are tracked (Lapse recordings,
  # or the Hackatime editor plugin for code; Other decides by the name you give it).
  def onboarding_tools
    [
      { id: "spreadsheet", name: "Spreadsheet", extension: ".xlsx", tracker: "lapse",
        phrases: [ "in Google Sheets", "in an Excel workbook", "drawn with conditional formatting", "where every cell is a pixel",
                   "that runs on checkboxes", "powered by iterative calc" ] },
      { id: "figma", name: "Figma", extension: ".fig", tracker: "lapse",
        phrases: [ "in Figma prototypes", "where frames are rooms", "run on Figma variables", "played in Present mode" ] },
      { id: "email", name: "Email", extension: ".eml", tracker: "lapse",
        phrases: [ "played over email", "where every reply is a turn", "run by inbox filters", "in your drafts folder" ] },
      { id: "ssh", name: "SSH", extension: ".sh", tracker: "hackatime",
        phrases: [ "over SSH", "in a login shell", "hiding in .bash_profile", "for a bare terminal" ] },
      { id: "shaders", name: "Shaders", extension: ".glsl", tracker: "hackatime",
        phrases: [ "in one fragment shader", "where state is pixels", "in a single GLSL file", "running only on the GPU" ] },
      { id: "other", name: "Other", extension: ".???", tracker: nil, phrases: [] }
    ].map { |tool| tool.merge(preposition: Project.preposition_for(tool[:id]), tracker_label: onboarding_tracker_label(tool[:tracker])) }
  end

  # Tools made for making games: the one answer to "does X count?" that's no. Matched as whole words in what you
  # type under Other.
  def onboarding_engines
    [ "unity", "unreal", "godot", "gamemaker", "game maker", "construct", "rpg maker", "pygame", "phaser", "love2d",
      "pico-8", "pico8", "scratch", "roblox", "bevy", "monogame", "libgdx", "cocos", "defold", "playcanvas", "babylon",
      "kaboom", "kaplay", "gdevelop", "stencyl", "renpy", "ren'py", "twine", "bitsy", "cryengine", "o3de", "flax",
      "game engine", "arcade library", "ursina", "panda3d", "heaps", "haxeflixel", "flixel", "melonjs", "excalibur" ]
  end

  # Quick answers under Other: the tools people keep asking about. Tapping one picks it.
  def onboarding_other_chips
    [ "Google Slides", "Google Docs", "PowerPoint", "Discord", "Notion", "CMake" ]
  end

  # What a tile says about its hours. Code in an editor counts through the Hackatime plugin; everything else is
  # recorded with Lapse, and one project can have both (Apps Script in an editor, formulas in the sheet).
  def onboarding_tracker_label(tracker)
    tracker == "hackatime" ? "Hackatime plugin" : "Lapse, or Hackatime for code"
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

  # How many consoles onboarding offers: few enough that each card has room for its photo. The rest wait in the shop.
  ONBOARDING_PRIZE_COUNT = 3

  # The consoles to pick from: the shelf's first few (Console.by_hours, the two prizes then the quickest), as the
  # prize cards show them, with about how many hours of building each is (Shop). The colour and extras are picked
  # on your handheld sheet later.
  def onboarding_prizes
    Console.by_hours.first(ONBOARDING_PRIZE_COUNT).map do |console|
      { id: console.id, maker: console.maker, name: console.name, full: console.full, kind: console.kind_label,
        image: console.image, alt: console.alt, hours: console.hours_for }
    end
  end
end
