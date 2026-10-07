require "test_helper"

class OnboardingHelperTest < ActionView::TestCase
  test "every genre and twist is its own idea, with the right article, short enough for a reel" do
    ideas = onboarding_rolled_ideas
    assert_equal onboarding_genres.size * onboarding_twists.size, ideas.uniq.size
    assert_operator ideas.size, :>=, 800
    assert_includes ideas, "a snake clone where the floor is lava"
    assert_includes ideas, "an escape room about tax season"
    assert_empty onboarding_twists.select { |twist| twist.length > 31 }
    assert_empty (onboarding_genres + onboarding_twists).reject { |word| word == word.downcase }
  end

  test "taken ideas are the rolled ones people have pledged, and how many times" do
    assert_empty onboarding_taken_ideas

    projects(:orpheus).update!(idea: "a snake clone where the floor is lava")
    projects(:ana).update!(idea: "a snake clone where the floor is lava")
    assert_equal({ "a snake clone where the floor is lava" => 2 }, onboarding_taken_ideas)
  end
end
