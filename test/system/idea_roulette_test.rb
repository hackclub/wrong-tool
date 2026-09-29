require "application_system_test_case"

class IdeaRouletteTest < ApplicationSystemTestCase
  setup { visit "/#ideas" }

  test "starts on a platformer in figma" do
    assert_selector ".ideas__result", text: "make a platformer in figma."
    assert_no_selector ".ideas__log-heading"
  end

  test "a spin settles both reels, then logs the idea" do
    click_on "Spin", exact: true
    assert_button "spinning…"

    assert_button "Spin", exact: true, wait: 3
    genre = find(".ideas__reel--genre").text
    platform = find(".ideas__reel--platform").text
    assert_selector ".ideas__result", exact_text: "make a #{genre} in #{platform}."
    assert_selector ".ideas__log-heading", text: "Past spins"
    assert_selector ".ideas__log-entry", count: 1, exact_text: "make a #{genre} in #{platform}"
  end

  test "keeps the last six spins, newest numbered highest" do
    7.times do
      click_on "Spin", exact: true
      assert_button "Spin", exact: true, wait: 3
    end

    assert_selector ".ideas__log-entry", count: 6
    assert_equal %w[6 5 4 3 2 1], all(".ideas__log-number").map(&:text)
  end
end
