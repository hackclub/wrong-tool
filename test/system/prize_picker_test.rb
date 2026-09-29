require "application_system_test_case"

class PrizePickerTest < ApplicationSystemTestCase
  test "the handhelds take turns being picked" do
    visit root_path

    assert_selector ".hero__prize[data-prize-picker-pick-value=rg35xx]"
    assert_selector ".hero__prize[data-prize-picker-pick-value=miyoo]", wait: 3
    assert_selector ".hero__prize[data-prize-picker-pick-value=rg35xx]", wait: 3
  end
end
