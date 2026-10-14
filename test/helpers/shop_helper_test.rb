require "test_helper"

class ShopHelperTest < ActionView::TestCase
  test "columns are named the way a sheet names them, past Z too, and a tile covers three" do
    assert_equal %w[A Z AA AB AZ BA ZZ AAA], [ 0, 25, 26, 27, 51, 52, 701, 702 ].map { |index| column_name(index) }
    assert_equal %w[H I J], shop_tile_columns("H4")
    assert_equal %w[Z AA AB], shop_tile_columns("Z4")
    assert_equal %w[AI AJ AK], shop_tile_columns("AI4")
  end
end
