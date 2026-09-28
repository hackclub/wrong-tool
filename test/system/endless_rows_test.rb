require "application_system_test_case"

class EndlessRowsTest < ApplicationSystemTestCase
  test "keeps a screenful of rows below the fold and adds more on scroll" do
    visit root_path
    assert rows_below_fold >= viewport_height

    count = all(".sheet__row-header").size
    execute_script("document.querySelector('.sheet-viewport').scrollTo(0, 1e6)")

    assert_selector ".sheet__row-header", minimum: count + 1
    assert rows_below_fold >= viewport_height
  end

  test "the selection can move past the rows the page started with" do
    visit root_path
    find(".sheet__cells").send_keys(*[ :down ] * 60)

    assert_selector "[data-cell-selection-target=nameBox]", exact_text: "B71"
  end

  private
    def viewport_height
      evaluate_script("document.querySelector('.sheet-viewport').clientHeight")
    end

    def rows_below_fold
      evaluate_script(<<~JS)
        (({ scrollTop, clientHeight, scrollHeight }) => scrollHeight - scrollTop - clientHeight)(document.querySelector(".sheet-viewport"))
      JS
    end
end
