# The consoles you can spend your hours on (Shop): what each one is, the colours it comes in, what its maker
# charges for it, and the extras its maker sells with it (a bigger card, a bag), each priced as the maker prices
# it, so a pick here is exactly one thing to order. The two we promised (`prize`) are Program::HOURS_PER_REWARD as
# they come, whatever they cost; everything else, and any extra, is its price through the shop's rates. Onboarding has you pick one (Project#prize); the shop lets you
# change it and pick its colour (Project#prize_color) and extras (Project#prize_options).
class Console
  Color = Data.define(:id, :name, :hex, :clear) do
    def initialize(id:, name:, hex:, clear: false) = super

    # "transparent teal", for a sentence.
    def label = name.downcase
  end

  # One of a maker's extras: what it adds to the price (0 for what's included).
  Choice = Data.define(:id, :name, :price) do
    def initialize(id:, name:, price: 0) = super
  end

  # A choice to make, one way or another: storage, a bag. `default` is the choice you get without saying.
  Option = Data.define(:id, :label, :choices, :default) do
    def initialize(id:, label:, choices:, default: nil)
      choices = choices.map { |choice| Choice.new(**choice) }.freeze
      super(id:, label:, choices:, default: default || choices.first.id)
    end

    def choice(id) = choices.find { |choice| choice.id == id }
  end

  Vendor = Data.define(:name, :url)

  KINDS = { "handheld" => "Handheld", "clamshell" => "Clamshell" }.freeze

  attr_reader :id, :maker, :name, :short, :kind, :screen, :blurb, :image, :alt, :url, :colors, :price, :vendor, :options

  def initialize(id:, maker:, name:, short:, kind:, screen:, blurb:, image:, alt:, url:, colors:, price:, vendor:, options: [], prize: false)
    @id, @maker, @name, @short, @kind, @screen, @blurb, @image, @alt, @url = id, maker, name, short, kind, screen, blurb, image, alt, url
    @prize = prize
    @colors = colors.map { |color| Color.new(**color) }.freeze
    @price = price
    @vendor = Vendor.new(**vendor)
    @options = options.map { |option| Option.new(**option) }.freeze
  end

  ANBERNIC = { name: "Anbernic's store", url: "https://anbernic.com" }.freeze
  MIYOO = { name: "Miyoo's store", url: "https://lomiyoo.com" }.freeze
  RETROID = { name: "Retroid's store", url: "https://www.goretroid.com" }.freeze
  POWKIDDY = { name: "Powkiddy's store", url: "https://www.powkiddy.com" }.freeze
  MODRETRO = { name: "ModRetro's store", url: "https://modretro.com" }.freeze
  # Anbernic sells the same card upgrades across its consoles (a second card, in the box with the one it comes with),
  # and a bag for each as its own $9.99 product.
  ANBERNIC_CARDS = { id: "storage", label: "SD Card",
                     choices: [ { id: "64", name: "64G" }, { id: "128", name: "64G+128G", price: 30 },
                                { id: "256", name: "64G+256G", price: 50 } ] }.freeze
  ANBERNIC_BAG = { id: "bag", label: "Bag", choices: [ { id: "no", name: "No bag" }, { id: "yes", name: "Protective bag", price: 9.99 } ] }.freeze
  # Retroid sells a $10 carrying case for some of its consoles, on its own.
  RETROID_CASE = { id: "bag", label: "Case", choices: [ { id: "no", name: "No case" }, { id: "yes", name: "Carrying Case", price: 10 } ] }.freeze
  # Miyoo sells each with a card or without; no bags.
  MIYOO_CARD = { id: "storage", label: "SD Card", default: "64",
                 choices: [ { id: "none", name: "No Card" }, { id: "64", name: "64GB", price: 5 } ] }.freeze

  # Each as its maker's own store sells it (url), colours and extras named as the store names them, at its prices,
  # and only what's in stock (from its China warehouse, the one that has stock).
  ALL = [
    new(id: "rg35xx", maker: "ANBERNIC", name: "RG35XX Pro", short: "RG35XX", kind: "handheld", screen: "3.5″",
        blurb: "Horizontal, with two sticks and a 3.5-inch screen. Comfortable for long sits.",
        image: "rewards/rg35xx-pro.webp", alt: "ANBERNIC RG35XX Pro handheld in transparent teal",
        url: "https://anbernic.com/products/rg35xxpro",
        colors: [ { id: "teal", name: "Transparent Teal", hex: "#2bb5a8", clear: true }, { id: "white", name: "White", hex: "#f2f2f0" },
                  { id: "black", name: "Black", hex: "#2a2a2a" } ],
        price: 54.99, vendor: ANBERNIC, options: [ ANBERNIC_CARDS, ANBERNIC_BAG ], prize: true),
    new(id: "miyoo", maker: "Miyoo", name: "Mini Plus", short: "Miyoo", kind: "handheld", screen: "3.5″",
        blurb: "Vertical and pocket-sized, with a 3.5-inch screen. The one that fits in jeans.",
        image: "rewards/miyoo-mini-plus.webp", alt: "Miyoo Mini Plus handheld in gray, front and back",
        url: "https://lomiyoo.com/products/miyoo-mini-plus",
        colors: [ { id: "grey", name: "Gray", hex: "#9a9a9a" }, { id: "white", name: "White", hex: "#f2f2f0" },
                  { id: "black", name: "Black", hex: "#3a3a3a", clear: true }, { id: "purple", name: "Purple", hex: "#8a5cc9", clear: true } ],
        price: 53.99, vendor: MIYOO, options: [ MIYOO_CARD ], prize: true),
    new(id: "rg35xxsp", maker: "ANBERNIC", name: "RG35XX SP", short: "RG35XX SP", kind: "clamshell", screen: "3.5″",
        blurb: "A clamshell the shape of a GBA SP. Shut it and it sleeps, open it and you're back in.",
        image: "rewards/rg35xx-sp.webp", alt: "ANBERNIC RG35XX SP clamshell in silver, open",
        url: "https://anbernic.com/products/rg35xxsp",
        colors: [ { id: "silver", name: "Silver", hex: "#c9cbce" }, { id: "grey", name: "Gray", hex: "#8f9094" },
                  { id: "black", name: "Black Transparent", hex: "#353535", clear: true },
                  { id: "green", name: "Green Transparent", hex: "#4caf50", clear: true } ],
        price: 57.99, vendor: ANBERNIC,
        options: [ ANBERNIC_CARDS, ANBERNIC_BAG.merge(choices: [ { id: "no", name: "No bag" }, { id: "yes", name: "Leather bag", price: 9.99 } ]) ]),
    new(id: "rg34xxsp", maker: "ANBERNIC", name: "RG34XX SP", short: "RG34XX SP", kind: "clamshell", screen: "3.4″",
        blurb: "The SP shape with a wider 3:2 screen, so Game Boy Advance games fill it edge to edge.",
        image: "rewards/rg34xx-sp.webp", alt: "ANBERNIC RG34XX SP clamshell in yellow, open",
        url: "https://anbernic.com/products/rg34xxsp",
        colors: [ { id: "yellow", name: "Yellow", hex: "#f3c320" }, { id: "grey", name: "Gray", hex: "#8f9094" },
                  { id: "black", name: "Black", hex: "#2a2a2a" }, { id: "indigo", name: "Indigo", hex: "#3f3d8f" },
                  { id: "blue", name: "Metallic Blue", hex: "#3a6fb0" } ],
        price: 67.99, vendor: ANBERNIC, options: [ ANBERNIC_CARDS, ANBERNIC_BAG ]),
    new(id: "miyooflip", maker: "Miyoo", name: "Mini Flip", short: "Miyoo Flip", kind: "clamshell", screen: "2.8″",
        blurb: "The Mini, folded in half. A 2.8-inch screen you'll forget is in your pocket.",
        image: "rewards/miyoo-mini-flip.webp", alt: "Miyoo Mini Flip clamshell in pink, open",
        url: "https://lomiyoo.com/products/miyoo-mini-flip",
        colors: [ { id: "pink", name: "Pink", hex: "#f2b8c0" }, { id: "grey", name: "Gray", hex: "#a9a9a9" },
                  { id: "white", name: "White", hex: "#f2f2f0" }, { id: "black", name: "Black", hex: "#2a2a2a" },
                  { id: "yellow", name: "Yellow", hex: "#f5c84b" } ],
        price: 49.99, vendor: MIYOO, options: [ MIYOO_CARD ]),
    new(id: "rg28xx", maker: "ANBERNIC", name: "RG28XX", short: "RG28XX", kind: "handheld", screen: "2.8″",
        blurb: "Tiny: a 2.8-inch screen in a horizontal shell, not much bigger than a credit card.",
        image: "rewards/rg28xx.webp", alt: "ANBERNIC RG28XX handheld in beige white",
        url: "https://anbernic.com/products/rg28xx",
        colors: [ { id: "beige", name: "Beige White", hex: "#e9e1cf" }, { id: "black", name: "Black Transparent", hex: "#353535", clear: true } ],
        price: 36.99, vendor: ANBERNIC,
        options: [ { id: "storage", label: "SD Card",
                     choices: [ { id: "32", name: "32G" }, { id: "128", name: "32G+128G", price: 30 }, { id: "256", name: "32G+256G", price: 50 } ] },
                   ANBERNIC_BAG ]),
    new(id: "rgdsplus", maker: "ANBERNIC", name: "RG DS Plus", short: "RG DS Plus", kind: "clamshell", screen: "4.3″",
        blurb: "Two 4.3-inch screens in a clamshell, the bottom one a touchscreen with a stylus, like a DS.",
        image: "rewards/anbernic-rg-ds-plus.webp", alt: "ANBERNIC RG DS Plus clamshell in metallic blue, open",
        url: "https://anbernic.com/products/rg-ds-plus",
        colors: [ { id: "blue", name: "Metallic Blue", hex: "#3a3f8f" }, { id: "black", name: "Matte Black", hex: "#2a2a2a" },
                  { id: "pink", name: "Coral Pink", hex: "#f2a7a0" } ],
        price: 94.99, vendor: ANBERNIC,
        options: [ { id: "storage", label: "SD Card",
                     choices: [ { id: "16", name: "16G" }, { id: "64", name: "16G+64G", price: 15 }, { id: "128", name: "16G+128G", price: 30 } ] },
                   ANBERNIC_BAG ]),
    new(id: "v90s", maker: "Powkiddy", name: "V90S", short: "V90S", kind: "clamshell", screen: "3.5″",
        blurb: "A clamshell for not much: shut it like a GBA SP, with two card slots inside.",
        image: "rewards/powkiddy-v90s.webp", alt: "Powkiddy V90S clamshell in transparent black, open",
        url: "https://www.powkiddy.com/products/pre-sale-powkiddy-v90s-handheld-game-console",
        colors: [ { id: "black", name: "Transparent Black", hex: "#353535", clear: true }, { id: "yellow", name: "YELLOW", hex: "#f5c84b" },
                  { id: "red", name: "RED", hex: "#d8453d" }, { id: "grey", name: "Grey", hex: "#8f9094" } ],
        price: 49.99, vendor: POWKIDDY,
        options: [ { id: "bag", label: "Bag", choices: [ { id: "no", name: "No bag" }, { id: "yes", name: "Case Storage Bag", price: 8.99 } ] } ]),
    new(id: "rpclassic", maker: "Retroid", name: "Pocket Classic", short: "Pocket Classic", kind: "handheld", screen: "3.92″",
        blurb: "Shaped like a Game Boy, with an OLED screen and a fan, so it stays cool for the long ones.",
        image: "rewards/retroid-pocket-classic.webp", alt: "Retroid Pocket Classic handheld in Classic 6 grey",
        url: "https://www.goretroid.com/products/retroid-pocket-classic",
        colors: [ { id: "classic6", name: "Classic 6", hex: "#d9d6cf" }, { id: "classic6sg", name: "Classic 6 SG", hex: "#bdbab3" },
                  { id: "yellow", name: "PKM Yellow", hex: "#f5d33b" }, { id: "retro", name: "Retro", hex: "#b3ab98" } ],
        price: 99.00, vendor: RETROID),
    new(id: "chromatic", maker: "ModRetro", name: "Chromatic", short: "Chromatic", kind: "handheld", screen: "2.56″",
        blurb: "Plays real Game Boy and Game Boy Color cartridges, and comes with Tetris. Runs on AA batteries.",
        image: "rewards/modretro-chromatic.webp", alt: "ModRetro Chromatic handheld in transparent smoke, playing Tetris",
        url: "https://modretro.com/products/chromatic-transparent",
        colors: [ { id: "smoke", name: "Smoke", hex: "#4a4a4a", clear: true }, { id: "purple", name: "Purple", hex: "#8a5cc9", clear: true },
                  { id: "green", name: "Green", hex: "#4caf50", clear: true }, { id: "red", name: "Red", hex: "#d8453d", clear: true } ],
        price: 149.99, vendor: MODRETRO,
        options: [ { id: "power", label: "Power", choices: [ { id: "aa", name: "AA batteries" }, { id: "core", name: "Rechargeable Power Core", price: 34.99 } ] },
                   { id: "bag", label: "Case", choices: [ { id: "no", name: "No case" }, { id: "yes", name: "Chromatic Case", price: 29.99 } ] } ]),
    new(id: "rpduolite", maker: "Retroid", name: "Pocket Duo Lite", short: "Duo Lite", kind: "clamshell", screen: "5.5″",
        blurb: "Two screens in a clamshell, the way a DS does it: a 5.5-inch one up top and a 4.2-inch one below.",
        image: "rewards/retroid-pocket-duo-lite.webp", alt: "Retroid Pocket Duo Lite clamshell in black, open",
        url: "https://www.goretroid.com/products/retroid-pocket-duo-lite-handheld",
        colors: [ { id: "black", name: "Black", hex: "#2a2a2a" }, { id: "gc", name: "GC", hex: "#5b5bc4" },
                  { id: "16bit", name: "16Bit", hex: "#cfccc5" }, { id: "iceblue", name: "Ice Blue", hex: "#a9d4ec" },
                  { id: "purple", name: "Clear Purple", hex: "#8a5cc9", clear: true } ],
        price: 149.00, vendor: RETROID,
        options: [ { id: "model", label: "Model", choices: [ { id: "lite4", name: "Lite 4+64" }, { id: "lite6", name: "Lite 6+128", price: 20 },
                                                             { id: "plus8", name: "Plus 8+128", price: 70 } ] } ]),
    new(id: "rp5", maker: "Retroid", name: "Pocket 5", short: "Pocket 5", kind: "handheld", screen: "5.5″",
        blurb: "A big 5.5-inch OLED and enough power for PS2 and GameCube, not just the old 8-bit stuff.",
        image: "rewards/retroid-pocket-5.webp", alt: "Retroid Pocket 5 handheld in GC purple",
        url: "https://www.goretroid.com/products/retroid-pocket-5-handheld",
        colors: [ { id: "gc", name: "GC", hex: "#5b5bc4" }, { id: "16bit", name: "16Bit", hex: "#cfccc5" }, { id: "black", name: "Black", hex: "#2a2a2a" },
                  { id: "yellow", name: "Yellow", hex: "#f5d33b" }, { id: "turquoise", name: "Turquoise", hex: "#3fb8b0" } ],
        price: 179.00, vendor: RETROID, options: [ RETROID_CASE ]),
    new(id: "rpflip2", maker: "Retroid", name: "Pocket Flip 2", short: "Flip 2", kind: "clamshell", screen: "5.5″",
        blurb: "The Pocket 5's power folded into a clamshell, with a 5.5-inch OLED that flips up.",
        image: "rewards/retroid-pocket-flip-2.webp", alt: "Retroid Pocket Flip 2 clamshell in black, open",
        url: "https://www.goretroid.com/products/retroid-pocket-flip-2",
        colors: [ { id: "black", name: "Black", hex: "#2a2a2a" }, { id: "gc", name: "GC", hex: "#5b5bc4" } ],
        price: 189.00, vendor: RETROID, options: [ RETROID_CASE ])
  ].freeze

  def self.ids = ALL.map(&:id)

  # The two we promised, at Program::HOURS_PER_REWARD.
  def self.prizes = ALL.select(&:prize?)

  # The two prizes first, then the rest by the hours they take (Shop): the shop's shelf, and onboarding's first few.
  def self.by_hours = ALL.each_with_index.sort_by { |console, order| [ console.prize? ? 0 : 1, console.hours_for, order ] }.map(&:first)

  def self.find(id) = ALL.find { |console| console.id == id }

  # "ANBERNIC RG35XX Pro"
  def full = "#{maker} #{name}"

  def kind_label = KINDS.fetch(kind)

  def clamshell? = kind == "clamshell"

  def prize? = @prize

  # One of its colours by id, or nil.
  def color(id) = colors.find { |color| color.id == id }

  # The one you get if you don't say.
  def default_color = colors.first

  def option(id) = options.find { |option| option.id == id }

  # Every option on its default: { "storage" => "64", "bag" => "no" }.
  def default_choices = options.to_h { |option| [ option.id, option.default ] }

  # The choices made (option id => choice id), with the defaults for any not made. Unknown options and choices are
  # left out: see Project's validation for saying no to them.
  def choices_for(picked)
    picked = self.class.picks(picked)
    options.to_h do |option|
      id = picked[option.id].to_s
      [ option.id, option.choice(id) ? id : option.default ]
    end
  end

  # What's wrong with these choices, if anything: options it doesn't have, or choices an option doesn't offer.
  def unknown_choices(picked)
    self.class.picks(picked).reject { |option_id, choice_id| option(option_id.to_s)&.choice(choice_id.to_s) }.keys.map(&:to_s)
  end

  # Choices as a hash of strings, from a hash, nothing, or the JSON they're stored as (which is how they arrive from
  # a server that started before the column did).
  def self.picks(picked)
    picked = JSON.parse(picked) if picked.is_a?(String)
    picked.to_h.to_h { |option, choice| [ option.to_s, choice.to_s ] }
  rescue JSON::ParserError
    {}
  end

  # Its price with these choices (defaults for any not made), as its maker charges it.
  def price_for(picked = {})
    (price + choices_for(picked).sum { |option_id, choice_id| option(option_id).choice(choice_id).price }).round(2)
  end

  # The hours it takes to afford, with these choices (Shop). A prize is Program::HOURS_PER_REWARD as it comes, and
  # an extra on it adds what the extra costs over that, through the rates (a cheaper choice takes nothing off).
  def hours_for(picked = {})
    return Shop.hours_for(price_for(picked)) unless prize?

    Shop.hours_for(Shop.dollars(Program::HOURS_PER_REWARD) + [ price_for(picked) - price_for, 0 ].max)
  end

  # Every way its options can be picked, and the hours each takes: { "bag=no|storage=64" => 12.0, ... }, keyed the
  # way shop_controller.js keys a pick, so the shop can total one without knowing what anything costs.
  def hours_table
    combinations = options.reduce([ {} ]) do |picks, option|
      picks.flat_map { |picked| option.choices.map { |choice| picked.merge(option.id => choice.id) } }
    end
    combinations.to_h { |picked| [ self.class.choices_key(picked), hours_for(picked) ] }
  end

  # "bag=no|storage=64": choices in one string, options in order.
  def self.choices_key(picked)
    picks(picked).sort.map { |option, choice| "#{option}=#{choice}" }.join("|")
  end

  # "anbernic.com": where it's ordered from, for the formula bar.
  def site = URI(vendor.url).host

  # The extras that cost something, for a sentence: "128 GB card, with a bag".
  def extras_label(picked = {})
    choices_for(picked).filter_map { |option_id, choice_id| (choice = option(option_id).choice(choice_id)).price.positive? ? choice.name.downcase_first : nil }
                       .join(", ").presence
  end
end
