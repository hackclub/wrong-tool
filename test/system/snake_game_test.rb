require "application_system_test_case"

class SnakeGameTest < ApplicationSystemTestCase
  setup { visit root_path }

  test "draws the starting snake and apple" do
    assert_selector ".snake-board__cell--head", count: 1
    assert_selector ".snake-board__cell--body", count: 2
    assert_selector ".snake-board__cell--food", count: 1

    find(".snake-board__cell--head").click
    assert_formula "=HEAD(snake)"
  end

  test "left alone, the snake runs into the wall" do
    click_on "▶ Play snake"
    assert_button "Playing · arrow keys steer"

    assert_button "▶ Game over. Play again", wait: 3
    assert_selector ".hero__score", text: "SCORE 0"
  end

  test "arrow keys steer the snake instead of moving the selection" do
    click_on "▶ Play snake"
    find(".sheet__cells").send_keys(:up)

    # Heading up from row 5 of the board, the head leaves row 5 and the selection stays put.
    assert_selector ".snake-board__cell--head" do |head|
      all(".snake-board__cell").index(head) < 20
    end
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "H10"
  end

  test "switching tabs stops the game" do
    click_on "▶ Play snake"
    click_on "FAQ"
    click_on "Hero"

    assert_button "▶ Play snake"
  end

  private
    def assert_formula(formula)
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
