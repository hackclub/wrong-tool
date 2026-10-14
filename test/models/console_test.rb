require "test_helper"

class ConsoleTest < ActiveSupport::TestCase
  test "every console is its own, has a photo in the app, a page on its maker's store, and comes in colours" do
    assert_equal Console.ids, Console.ids.uniq
    assert_equal Console.ids, Project::PRIZES

    Console::ALL.each do |console|
      assert Rails.root.join("app/assets/images", console.image).exist?, "#{console.id} is missing #{console.image}"
      assert_operator console.colors.size, :>=, 2, "#{console.id} needs colours to pick from"
      assert_equal console.colors.map(&:id), console.colors.map(&:id).uniq
      assert_match(/\A#\h{6}\z/, console.colors.first.hex)
      assert_includes Console::KINDS.keys, console.kind
      assert_match %r{\A#{Regexp.escape(console.vendor.url)}/products/}, console.url
    end
  end

  test "there are handhelds and clamshells, and the two from the landing page are still there" do
    assert_equal %w[rg35xx miyoo], Console.ids.first(2)
    assert_operator Console::ALL.count(&:clamshell?), :>=, 2
    assert_operator Console::ALL.count { |console| !console.clamshell? }, :>=, 2
  end

  test "each console is priced as its maker prices it, with the maker's extras one to one" do
    Console::ALL.each do |console|
      assert_operator console.price, :>, 0
      assert_equal console.price_for, console.price_for(console.default_choices)
      assert_match %r{\Ahttps://}, console.vendor.url
      console.options.each do |option|
        assert option.choice(option.default), "#{console.id}'s #{option.id} default should be one of its choices"
        assert_equal option.choices.map(&:id), option.choices.map(&:id).uniq
      end
    end

    sp = Console.find("rg35xxsp")
    assert_equal 57.99, sp.price_for
    assert_equal 97.98, sp.price_for("storage" => "128", "bag" => "yes") # $30 for the second card, $9.99 for the bag
    assert_equal({ "storage" => "128", "bag" => "no" }, sp.choices_for("storage" => "128", "case" => "yes", "bag" => "maybe"))
    assert_equal [ "case", "bag" ], sp.unknown_choices("storage" => "128", "case" => "yes", "bag" => "maybe")
    assert_equal "64G+128G, leather bag", sp.extras_label("storage" => "128", "bag" => "yes")
    assert_nil sp.extras_label
    assert_equal 97.98, sp.price_for('{"storage":"128","bag":"yes"}'), "the JSON they're stored as, from a stale server"
    assert_equal 57.99, sp.price_for("not json")
    assert_equal 12.0, sp.hours_for
    assert_equal 22, sp.hours_for("storage" => "128", "bag" => "yes")

    # The two we promised are 10 hours as they come, whatever they cost; an extra adds what it costs over that, at
    # $4 an hour, and a cheaper choice takes nothing off.
    assert_equal %w[rg35xx miyoo], Console.prizes.map(&:id)
    assert_equal 10.0, Console.find("rg35xx").hours_for
    assert_equal 18, Console.find("rg35xx").hours_for("storage" => "128")
    assert_equal 13, Console.find("rg35xx").hours_for("bag" => "yes")
    assert_equal 10.0, Console.find("miyoo").hours_for
    assert_equal 10.0, Console.find("miyoo").hours_for("storage" => "none")
    assert_nil Console.find("miyoo").option("bag"), "Miyoo's store doesn't sell one"
    assert_not sp.prize?

    # The Miyoo's default is a card you can use it with, not the cheapest listing.
    miyoo = Console.find("miyoo")
    assert_equal "64", miyoo.option("storage").default
    assert_equal 58.99, miyoo.price_for
    assert_equal 53.99, miyoo.price_for("storage" => "none")
  end

  test "a console knows its colours, its full name and what to call a colour in a sentence" do
    console = Console.find("rg35xx")
    assert_equal "ANBERNIC RG35XX Pro", console.full
    assert_equal "Transparent Teal", console.default_color.name
    assert_equal "transparent teal", console.default_color.label
    assert console.default_color.clear
    assert_equal "White", console.color("white").name
    assert_nil console.color("plaid")
    assert_nil Console.find("switch")
  end

  test "a console tables the hours every way of picking it takes, keyed like the shop keys a pick, and knows its site" do
    sp = Console.find("rg35xxsp")
    table = sp.hours_table
    assert_equal 6, table.size, "three cards by two bags"
    assert_equal 12.0, table.fetch("bag=no|storage=64")
    assert_equal 22, table.fetch("bag=yes|storage=128")
    assert_equal "bag=yes|storage=128", Console.choices_key("storage" => "128", bag: "yes")
    assert_equal "anbernic.com", sp.site
    assert_equal "lomiyoo.com", Console.find("miyoo").site
    assert_equal 6, Console.find("rg28xx").hours_table.size
  end
end
