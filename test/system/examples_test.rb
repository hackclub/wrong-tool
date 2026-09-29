require "application_system_test_case"

class ExamplesTest < ApplicationSystemTestCase
  setup { visit "/#examples" }

  test "shows every example, flap last" do
    assert_selector ".examples__card", count: 6
    assert_selector ".examples__all", text: "All"
    assert_selector ".examples__count", exact_text: "6"
    assert_no_text "pure css"
    assert_link "Doom Bookmarklet ↗", href: "https://github.com/PianoMan0/Doom-Bookmarklet"
    assert_link "CSS Aim Trainer ↗", href: "https://ascpixi.dev/css-aim-trainer/"
    assert_link "ascii3d ↗", href: "https://github.com/0xMarta/ascii3d"
    assert_equal "flap in the sheets ↗", all(".examples__name").last.text
  end

  test "cards flow three to a row" do
    all(".examples__name")[3].click

    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "B21"
  end
end
