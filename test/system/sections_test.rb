require "application_system_test_case"

class SectionsTest < ApplicationSystemTestCase
  test "cells in table rows land on the right address" do
    visit "/#how-it-works"
    all(".how-it-works__step--item")[2].click

    assert_selection "C10", formula: "Put it in a git repo"
  end

  test "how it works numbers its steps and links the hour trackers" do
    visit "/#how-it-works"
    assert_selector ".how-it-works__number--step", count: 4
    assert_text "Submit your repo and hours by oct 16."
    new_window = window_opened_by { click_link "Lapse ↗" } # not covered by the repo table beside it
    assert_equal "https://lapse.hackclub.com/", within_window(new_window) { current_url }
    new_window.close

    within(all(".how-it-works__detail--item")[1]) do
      assert_link "Hackatime", href: "https://hackatime.hackclub.com/"
      assert_link "Lapse", href: "https://lapse.hackclub.com/"
    end
    assert_link "Hackatime ↗", href: "https://hackatime.hackclub.com/"
    assert_link "Lapse ↗", href: "https://lapse.hackclub.com/"
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
    { "hero" => "B21", "how-it-works" => "B21", "ideas" => "B22", "faq" => "B19" }.each do |section, address|
      visit "/##{section}"
      find("##{section} .sheet-footer__text").click
      assert_selection address, formula: "Made with ♥ by teenagers, for teenagers at Hack Club — a 501(c)(3) nonprofit and a network of 100k+ technical high schoolers."
    end

    find("#faq .sheet-footer__links a", text: "slack").click
    assert_selection "B21", formula: '=HYPERLINK("https://hackclub.com/slack/", "slack")'
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
