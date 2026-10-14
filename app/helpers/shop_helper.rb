# The shop, as the design draws it: a shelf of consoles built out of the sheet's own cells, Clippy at the counter,
# and everything in hours (Shop keeps the prices to itself). What he says is in the nudges' voice (Nudge::Copy): a
# plain, short, lowercase line, with a Slack emote on the end where one fits (ApplicationHelper#emotes draws it).
module ShopHelper
  # The shelf: the two prizes we promised (10 hrs as they come), then, past a column of empty cells, the rest by the
  # hours they take. The tiles start at row 4 (row 3 is empty cells), three columns wide, so the first sits at A4,
  # the next at D4, and the first of the rest at H4.
  SHELF_ROW = 4
  TILE_COLUMNS = 3

  # Where a tile is in its day: locked (hours to go), unlocked (your unspent logged hours cover it; ship your game,
  # or ship again, so they're approved), ready (what's left of your approved hours covers it: buy it) and shipping
  # (bought: in the queue, then ordered). Approved hours are spent like money, on one of each console. What each
  # says in the tile's corner.
  TAGS = { "unlocked" => "ship first", "ready" => "ready" }.freeze
  CLAIMED_TAGS = { "waiting" => "in the queue", "ordered" => "ordered" }.freeze

  def shop_shelf(project)
    Console.by_hours.each_with_index.map do |console, index|
      yours = console == project.console
      order = project.order_for(console.id)
      choices = if order then order.prize_options
      elsif yours then project.prize_choices
      else console.default_choices
      end
      hours = order ? order.hours.to_f : console.hours_for(choices)
      to_go = [ (hours - project.hours_unspent_logged).round(1), 0 ].max
      state = shop_state(project, order:, hours:)
      { console:, cell: "#{column_name(index * TILE_COLUMNS + (console.prize? ? 0 : 1))}#{SHELF_ROW}", yours:, choices:, hours:, to_go:, state:,
        color: order&.color || (yours ? project.console_color : console.default_color), order: order&.status,
        tag: shop_tag(project, state, to_go, order) }
    end
  end

  # A column's letters, the way a sheet names them, from 0: A … Z, AA, AB …
  def column_name(index)
    index < 26 ? ("A".ord + index).chr : column_name(index / 26 - 1) + column_name(index % 26)
  end

  # The column letters a tile at this cell covers: "H4" → H, I, J.
  def shop_tile_columns(cell)
    first = cell[/\A[A-Z]+/].chars.reduce(0) { |index, letter| index * 26 + letter.ord - 64 } - 1
    Array.new(TILE_COLUMNS) { |offset| column_name(first + offset) }
  end

  def shop_state(project, order:, hours:)
    if order then "shipping"
    elsif project.hours_to_spend >= hours then "ready"
    elsif project.hours_unspent_logged >= hours then "unlocked"
    else "locked"
    end
  end

  def shop_tag(project, state, to_go, order)
    case state
    when "locked" then "#{project_hours(to_go)} to go"
    when "shipping" then CLAIMED_TAGS.fetch(order.status)
    when "unlocked" then project.shipped? ? "ship again" : TAGS.fetch(state)
    else TAGS.fetch(state)
    end
  end

  # "12 hrs"
  def shop_hours(hours)
    "#{project_hours(hours)} hrs"
  end

  # What a choice adds against the option's default, in hours, with the tile's other choices as they are: "+7.5 hrs",
  # "−2.5 hrs", or "included".
  def shop_choice_hours(console, choices, option, choice)
    difference = (console.hours_for(choices.merge(option.id => choice.id)) - console.hours_for(choices.merge(option.id => option.default))).round(1)
    return "included" if difference.zero?
    "#{difference.positive? ? "+" : "−"}#{project_hours(difference.abs)} #{difference.abs == 1 ? "hr" : "hrs"}"
  end

  # "Transparent teal · 128 GB card": the colour, and any extra that isn't what it comes with.
  def shop_variant(tile)
    extras = tile[:console].options.filter_map do |option|
      choice = tile[:choices][option.id]
      option.choice(choice).name.downcase_first unless choice == option.default
    end
    [ tile[:color].name, *extras ].join(" · ")
  end

  # =PICK("rg35xx", "teal")  →  6.5 of 12 hrs
  def shop_formula(project)
    %(=PICK("#{project.prize}", "#{project.console_color.id}")  →  #{project_hours_label(project)})
  end

  # On the sheet tabs: how far your pick is.
  def shop_sum(project)
    name = project.console.name
    if (order = project.order_for(project.prize)) then "#{name} · #{CLAIMED_TAGS.fetch(order.status)}"
    elsif project.claimable? then "#{name} · ready"
    elsif project.afford? then "#{name} · hours in"
    else "#{name} · #{project_hours(project.hours_to_go)} hrs to go"
    end
  end

  # The ship cell next to your hours: whether you've shipped, and how that went.
  def shop_ship_status(project)
    if project.shipped? then [ "#{project_hours(project.hours_to_spend)} hrs", "done" ]
    elsif project.ship_in_review then [ "in review", "review" ]
    else [ "not yet", "none" ]
    end
  end

  # What Clippy says when you come in (or after you've picked something: `picked`).
  def shop_says(project, picked: false)
    console = project.console
    name = "#{console.name} in #{project.console_color.label}"
    hours = project_hours(project.hours_logged)
    to_go = project_hours(project.hours_to_go)
    to_spend = project_hours(project.hours_to_spend)
    if (order = project.order_for(project.prize))
      bought = order.ordered? ? "your #{name} is ordered." : "your #{name} is bought. someone will order it soon."
      project.hours_to_spend.positive? ? "#{bought} #{to_spend} hours left to spend." : "#{bought} :yay:"
    elsif project.claimable?
      "#{to_spend} hours to spend. that covers the #{name}, so it's yours to buy. :yay:"
    elsif picked
      project.afford? ? "#{name}. your hours cover it, so ship your game and it's yours. :yay:" : "#{name}. #{to_go} hours to go."
    elsif !project.tracking? then "link hackatime on your sheet and your hours will show up here."
    elsif project.hours_logged.zero? then "nothing logged yet. the #{console.name} is #{project_hours(project.hours_needed)} hours."
    elsif project.afford? && project.shipped? then "#{to_spend} hours to spend. ship again so the rest count for the #{name}."
    elsif project.afford? then "your hours cover the #{name}. ship your game and it's yours. :yay:"
    else "#{hours} hours so far, #{to_go} to go for the #{name}."
    end
  end

  # The emotes the counter uses, as pictures (SlackEmoji), for lines said as you go.
  # Asking for another seller (SellerRequest), as the shop shows it: the link, where it is, and how it's going.
  ASK_STATUSES = { "pending" => "in review", "approved" => "approved", "denied" => "not this one" }.freeze

  def shop_ask_data(ask)
    { url: ask.url, host: ask.host, status: ask.status, label: ASK_STATUSES.fetch(ask.status) }
  end

  # The latest ask for each console the project's asked about: { "miyoo" => { url:, host:, status:, label: } }.
  def shop_asks_data(project)
    project.seller_requests.order(:created_at).to_h { |ask| [ ask.prize, shop_ask_data(ask) ] }
  end

  # The Seller row on the Customize panel: the console's store, or the seller you asked for and how it's going.
  def shop_seller(console, ask)
    return [ console.vendor.name, console.url ] if ask.nil? || ask[:status] == "denied"

    [ "#{ask[:host]} · #{ask[:label]}", ask[:url] ]
  end

  def shop_emotes_data
    %w[yay].to_h { |name| [ name, SlackEmoji.url(name) ] }.compact
  end

  # How Clippy feels (a mood in mascot/clippy.js).
  def shop_mood(project)
    if project.claimable? || project.afford? then "happy"
    elsif !project.tracking? then "attention"
    else "idle"
    end
  end

  # The shelf for shop_controller.js: each console with the hours every way of picking it takes.
  def shop_consoles_data(shelf)
    shelf.map do |tile|
      console = tile[:console]
      { id: console.id, name: console.full, short: console.name, maker: console.maker, kind: console.kind, prize: console.prize?, screen: console.screen,
        blurb: console.blurb, image: image_path(console.image), alt: console.alt, site: console.site, vendor: console.vendor.name, url: console.url, cell: tile[:cell],
        colors: console.colors.map { |color| { id: color.id, name: color.name, hex: color.hex, clear: color.clear } },
        options: console.options.map do |option|
          { id: option.id, label: option.label, default: option.default, choices: option.choices.map { |choice| { id: choice.id, name: choice.name } } }
        end,
        hours: console.hours_table }
    end
  end

  # What each tile starts on: yours as you picked it, the others on their defaults.
  def shop_configs_data(shelf)
    shelf.to_h { |tile| [ tile[:console].id, { color: tile[:color].id, options: tile[:choices] } ] }
  end

  # The pick as JSON, for the shop after it saves a change.
  # After buying: the order, what's left to spend, and the sheet's sum and formula.
  def shop_order_data(project, order)
    { prize: order.prize, order: order.status, hours_to_spend: project.hours_to_spend, hours_spent: project.hours_spent,
      sum: shop_sum(project),
      formula: %(=BUY("#{order.prize}", "#{order.prize_color}")  →  #{project_hours(project.hours_to_spend)} hrs left) }
  end

  def shop_state_data(project, picked: true)
    { prize: project.prize, prize_color: project.console_color.id, prize_options: project.prize_choices,
      hours_logged: project.hours_logged, hours_to_spend: project.hours_to_spend, hours_spent: project.hours_spent,
      hours_needed: project.hours_needed, to_go: project.hours_to_go, afford: project.afford?,
      says: shop_says(project, picked:), sum: shop_sum(project), formula: shop_formula(project) }
  end

  # Small icons for the choices and the shelf, drawn here so nothing's fetched.
  ICONS = {
    info: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 11v6M12 7.25v.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
    palette: '<path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-.9 2-2 0-.6-.3-1-.5-1.4-.3-.5-.5-.9-.5-1.6 0-1 .9-2 2-2h2a4 4 0 0 0 4-4c0-4-4-7-9-7Z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="7.5" cy="12" r="1.3"/><circle cx="10" cy="8" r="1.3"/><circle cx="14.5" cy="8" r="1.3"/><circle cx="17" cy="12" r="1.3"/>',
    card: '<path d="M8 3h10a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V8l3-5Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M10 7v3M13 7v3M16 7v3" stroke="currentColor" stroke-width="2"/>',
    extra: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 8v8M8 12h8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
    flag: '<path d="M5 21V4h9l.5 2H20v9h-6.5l-.5-2H7v8H5Z"/>',
    back: '<path d="M14 6l-6 6 6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
    store: '<path d="M4 10 5.5 4h13L20 10M4 10v10h16V10M4 10h16M9 20v-6h6v6" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
    send: '<path d="M4 12 20 4l-4 16-4-7-8-1Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
    zoom: '<circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M15.5 15.5 21 21M8 10.5h5M10.5 8v5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
    chevron_left: '<path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>',
    chevron_right: '<path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>'
  }.freeze

  def shop_icon(name, class_name = nil)
    tag.svg(ICONS.fetch(name).html_safe, class: [ "icon", class_name ], viewBox: "0 0 24 24", aria: { hidden: true })
  end
end
