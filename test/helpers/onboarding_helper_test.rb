require "test_helper"

class OnboardingHelperTest < ActionView::TestCase
  include ApplicationHelper
  include ProjectsHelper

  test "every genre and twist is its own idea, with the right article, short enough for a reel" do
    ideas = onboarding_rolled_ideas
    assert_equal onboarding_genres.size * onboarding_twists.size, ideas.uniq.size
    assert_operator ideas.size, :>=, 800
    assert_includes ideas, "a snake clone where the floor is lava"
    assert_includes ideas, "an escape room about tax season"
    assert_empty onboarding_twists.select { |twist| twist.length > 31 }
    assert_empty (onboarding_genres + onboarding_twists).reject { |word| word == word.downcase }
  end

  test "the engines list is what's not allowed, and the quick answers are tools people ask about" do
    assert_includes onboarding_engines, "unity"
    assert_includes onboarding_engines, "godot"
    assert_not_includes onboarding_engines, "raylib" # not an engine, as ruled in #wrong
    assert_equal [ "Google Slides", "Google Docs", "PowerPoint", "Discord", "Notion", "CMake" ], onboarding_other_chips
    assert_empty onboarding_engines.reject { |engine| engine == engine.downcase }
  end

  test "the prize cards are three consoles, the prizes then the quickest, with a photo each" do
    prizes = onboarding_prizes
    assert_equal %w[rg35xx miyoo rg28xx], prizes.map { |prize| prize[:id] }
    assert_equal({ id: "rg35xx", maker: "ANBERNIC", name: "RG35XX Pro", full: "ANBERNIC RG35XX Pro", kind: "Handheld",
                   image: "rewards/rg35xx-pro.webp", alt: "ANBERNIC RG35XX Pro handheld in transparent teal", hours: 10.0 }, prizes.first)
    assert_equal 8, prizes.find { |prize| prize[:id] == "rg28xx" }[:hours]
  end

  test "taken ideas are the rolled ones people have pledged, and how many times" do
    assert_empty onboarding_taken_ideas

    projects(:orpheus).update!(idea: "a snake clone where the floor is lava")
    projects(:ana).update!(idea: "a snake clone where the floor is lava")
    assert_equal({ "a snake clone where the floor is lava" => 2 }, onboarding_taken_ideas)
  end
end
