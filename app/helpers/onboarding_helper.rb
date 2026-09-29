module OnboardingHelper
  # The four questions, one per cell down column A.
  def onboarding_steps
    [
      { label: "Wrong tool", question: "Pick your wrong tool.",
        help: "Anything not built for games. You can switch later." },
      { label: "Building", question: "What are you building?",
        help: "A starting point. Roll again, write your own, or skip." },
      { label: "Prize", question: "Pick your prize.",
        help: "Pick one. It ships once you log #{hours_per_reward} hours." },
      { label: "Save", question: "Save your project.",
        help: "Saves your tool, idea and prize to your Hack Club account." }
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
    ]
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
