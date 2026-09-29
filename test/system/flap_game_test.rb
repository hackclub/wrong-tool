require "application_system_test_case"

class FlapGameTest < ApplicationSystemTestCase
  setup { visit root_path }

  test "starts on the original's first frame" do
    assert_selector ".flap__pixel--bird", count: 12
    assert_selector ".flap__pixel--beak", count: 2
    assert_selector ".flap__pixel--cap-edge", count: 8
    assert_selector ".flap__score", text: "score 0 · best 0"
  end

  test "FLAP starts the game and, left alone, the bird falls and crashes" do
    click_on "FLAP!"
    assert_selector ".flap__board--running"

    assert_no_selector ".flap__board--running", wait: 5
    assert_selector ".flap__pixel--bird", count: 12 # the crash frame stays on the board
  end

  test "space flaps instead of moving the selection" do
    find(".sheet__cells").send_keys(:space)

    assert_selector ".flap__board--running"
    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "B11"
  end

  test "switching tabs pauses the game" do
    click_on "FLAP!"
    click_on "FAQ"
    click_on "Hero"

    assert_no_selector ".flap__board--running"
  end

  test "links the real game" do
    assert_link "cskartikey.dev/flap ↗", href: "https://cskartikey.dev/flap"
  end
end
