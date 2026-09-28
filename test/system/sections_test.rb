require "application_system_test_case"

class SectionsTest < ApplicationSystemTestCase
  test "cells in table rows land on the right address" do
    visit "/#rules"
    all(".rules__allowed.cell--false").first.click

    assert_selection "I8", formula: "=RUNS_IN_MEDIUM(B8) → FALSE"
  end

  test "the gallery's second row starts on row 11" do
    visit "/#gallery"
    all(".gallery__image")[4].click

    assert_selection "B11", formula: '=IMAGE("amet (ssh).png")'
  end

  test "an input cell keeps focus and shows its value in the formula bar" do
    visit "/#reward"
    input = find(".reward__hours input")
    input.click

    assert_selection "B7", formula: "12"
    assert_equal input, page.active_element
  end

  private
    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
