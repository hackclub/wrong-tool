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
      { id: "email", name: "Email", extension: ".eml", preposition: "over",
        phrases: [ "played over email", "where every reply is a turn", "run by inbox filters", "in your drafts folder" ] },
      { id: "ssh", name: "SSH", extension: ".sh", preposition: "over",
        phrases: [ "over SSH", "in a login shell", "hiding in .bash_profile", "for a bare terminal" ] },
      { id: "shaders", name: "Shaders", extension: ".glsl",
        phrases: [ "in one fragment shader", "where state is pixels", "in a single GLSL file", "running only on the GPU" ] },
      { id: "other", name: "Other", extension: ".???", phrases: [] }
    ]
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

  def onboarding_prizes
    [
      { id: "rg35xx", maker: "ANBERNIC", name: "RG35XX Pro", full: "ANBERNIC RG35XX Pro",
        image: "rewards/rg35xx-pro.webp", alt: "ANBERNIC RG35XX Pro handheld in transparent teal" },
      { id: "miyoo", maker: "MIYOO", name: "Mini Plus", full: "Miyoo Mini Plus",
        image: "rewards/miyoo-mini-plus.webp", alt: "Miyoo Mini Plus handheld in grey, front and back" }
    ]
  end
end
