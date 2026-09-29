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

  test "the reward shows both handhelds as selectable image cells" do
    visit "/#reward"
    assert_selector "img[alt^='ANBERNIC RG35XX Pro']"
    assert_selector "img[alt^='Miyoo Mini Plus']"

    find("img[alt^='Miyoo Mini Plus']").click
    assert_selection "K2", formula: '=IMAGE("miyoo-mini-plus.webp")'
  end

  test "the hero offers both handhelds" do
    visit root_path
    find(".hero__marquee").click
    assert_selection "B13", formula: "=SHIP(handheld) every 10 hrs"

    find(".hero__photo.hero__handheld--miyoo").click
    assert_selection "E14", formula: '=IMAGE("miyoo-mini-plus.webp")'

    find(".hero__or").click
    assert_selection "D14", formula: '=OR("RG35XX Pro", "Miyoo Mini Plus")'

    find(".hero__caption.hero__handheld--rg35xx").click
    assert_selection "B18", formula: '=SHIP(handheld, "RG35XX Pro")'
  end

  test "every sheet ends with the footer, two rows below its content" do
    { "hero" => "B21", "faq" => "B19", "reward" => "B13" }.each do |section, address|
      visit "/##{section}"
      find("##{section} .sheet-footer__text").click
      assert_selection address, formula: "Made with ♥ by teenagers, for teenagers at Hack Club — a 501(c)(3) nonprofit and a network of 100k+ technical high schoolers."
    end

    find("#reward .sheet-footer__links a", text: "slack").click
    assert_selection "B15", formula: '=HYPERLINK("https://hackclub.com/slack/", "slack")'
  end

  test "the hero leads with the program name" do
    visit root_path
    find(".hero__name").click
    assert_selection "B3", formula: '=YSWS("wrong tool")'
  end

  private
    def assert_selection(address, formula:)
      assert_selector "[data-cell-selection-target=nameBox]", exact_text: address
      assert_equal formula, find("[data-cell-selection-target=formula]", visible: :all).text(:all)
    end
end
