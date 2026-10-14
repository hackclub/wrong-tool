import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"

// The shop's counter. The shelf is six tiles; one's selected (the ring with "You" on it), and Clippy talks about
// it in the nudges' voice: a plain, short line that types itself out (click to skip), with a Slack emote on the
// end where one fits, and your answers as the choices under it, ↑ ↓ and Enter or a tap. Asking for the same
// console from another seller, to save on customs, takes a link to the listing (a POST to /shop/seller_requests),
// which an admin checks; the tile says how that's going. ← → move along the shelf. Each tile remembers the colour and extras you've tried on
// it; on your pick those save as you make them (a PATCH to /shop, as JSON), and "Make it my pick" on another
// saves it as you've set it up. Everything's in hours: each console carries a table of the hours every way of
// picking it takes, so nothing here knows a price.
export default class extends Controller {
  static targets = [
    "grid", "nameBox", "formula", "tile", "cost", "tag", "shelf", "left", "right", "moreText", "range", "dot",
    "counter", "mascot", "sprite", "say", "typed", "ask", "askInput", "choices", "customize", "customizeName", "seller", "variant", "swatches", "colorName",
    "options", "costFormula", "customizeCost", "sum", "columnHeader", "rowHeader", "addressForm", "toSpend"
  ]
  static values = {
    consoles: Array, configs: Object, pick: String, hours: Number, tracking: Boolean, shipped: Boolean,
    toSpend: Number, spent: Number, orders: Object, claimUrl: String, needsAddress: Boolean, url: String, askUrl: String, asks: Object, says: String, emotes: Object, mood: String, sounds: Object
  }

  connect() {
    this.configs = structuredClone(this.configsValue)
    this.selected = this.pickValue
    this.talk = "main"
    this.marked = -1
    this.asks = structuredClone(this.asksValue)
    this.clippy = new Clippy(this.spriteTarget, this.soundsValue)
    this.clippy.feel(this.moodValue || "idle")
    // An emote whose picture won't load (Slack's, offline) is its name, as it'd be anywhere else.
    this.sayTarget.addEventListener("error", ({ target }) => target.replaceWith(target.alt), true)
    this.#render()
    this.#say(this.saysValue)
    this.scrolled()
  }

  disconnect() {
    this.clippy.stop()
    clearInterval(this.typer)
    clearTimeout(this.hopTimer)
  }

  // The shelf

  select(event) {
    event.preventDefault()
    this.#select(event.currentTarget.closest("[data-console]").dataset.console)
  }

  jump({ currentTarget }) {
    this.#select(currentTarget.dataset.console)
  }

  scrollLeft() {
    this.shelfTarget.scrollBy({ left: -this.#tileWidth() * 2, behavior: "smooth" })
  }

  scrollRight() {
    this.shelfTarget.scrollBy({ left: this.#tileWidth() * 2, behavior: "smooth" })
  }

  // Where you are along it: the back button once there's something behind, "n more" while there's more ahead (any
  // tile not wholly on screen), the range of cells on screen and a dot per tile that is.
  scrolled() {
    const shelf = this.shelfTarget
    const width = this.#tileWidth()
    if (!width) return
    const start = shelf.scrollLeft
    const end = start + shelf.clientWidth
    const shown = this.tileTargets.map((tile) => tile.offsetLeft >= start - 1 && tile.offsetLeft + width <= end + 1)
    const first = Math.max(shown.indexOf(true), 0)
    const last = Math.max(shown.lastIndexOf(true), first)
    const ahead = this.tileTargets.length - last - 1
    this.leftTarget.hidden = first === 0
    this.rightTarget.hidden = ahead === 0
    this.moreTextTarget.textContent = `${ahead} more`
    const lastColumn = columnName(Math.round(end / CELL_WIDTH) - 1)
    this.rangeTarget.textContent = `${this.#console(this.#ids()[first]).cell}:${lastColumn}${SHELF_ROW + SHELF_ROWS - 1}`
    this.dotTargets.forEach((dot, index) => dot.toggleAttribute("data-on", shown[index]))
  }

  // The keys, once you've clicked into the grid.
  key(event) {
    if (event.target.matches("input, textarea")) return
    const handlers = {
      ArrowLeft: () => this.#step(-1), ArrowRight: () => this.#step(1),
      ArrowUp: () => this.#mark(-1), ArrowDown: () => this.#mark(1),
      Enter: () => (this.sayTarget.hasAttribute("data-typing") ? this.#finishTyping() : this.marked >= 0 && this.#answer(this.marked)),
      Escape: () => (this.talk === "main" ? this.#finishTyping() : this.#talkTo("main"))
    }
    if (!handlers[event.key] || event.metaKey || event.ctrlKey || event.altKey) return
    event.preventDefault()
    handlers[event.key]()
  }

  // The counter

  choose({ currentTarget }) {
    this.#answer(Number(currentTarget.dataset.index))
  }

  skip() {
    this.#finishTyping()
  }

  pickColor({ currentTarget }) {
    this.#setColor(currentTarget.dataset.color)
  }

  pickChoice({ currentTarget }) {
    this.#setChoice(currentTarget.dataset.option, currentTarget.dataset.choice)
  }

  // The link to another seller's listing, for this tile. Sent for an admin to check, and shown as in review.
  async sendAsk(event) {
    event.preventDefault()
    const url = this.askInputTarget.value.trim()
    if (!url) return
    const id = this.selected
    const token = document.querySelector("meta[name='csrf-token']")?.content
    let data
    try {
      const response = await fetch(this.askUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ seller_request: { prize: id, url } })
      })
      data = await response.json()
      if (!response.ok) throw new Error(data.error)
    } catch (error) {
      this.#say(lower(error.message || "that didn't send. try again."))
      return
    }
    this.asks[id] = data
    this.askInputTarget.value = ""
    this.#fx(`=REQUEST(seller, "${this.#console(id).short}")  →  ${data.label}`)
    this.#hop()
    this.#talkTo("main")
    this.#renderCustomize()
    this.#say("got it. someone will check the link and let you know on slack.")
  }

  // What's where

  #ids() {
    return this.consolesValue.map((console) => console.id)
  }

  #console(id) {
    return this.consolesValue.find((console) => console.id === id)
  }

  // The tile's ask for another seller, while it's in review or approved (ShopHelper#shop_seller).
  #liveAsk(id) {
    const ask = this.asks[id]
    return ask && ask.status !== "denied" ? ask : null
  }

  #tileWidth() {
    return this.tileTargets[0]?.offsetWidth ?? 0
  }

  // The letters of a tile's first column, `offset` columns on: the third tile starts at H, so H, I, J.
  #column(id, offset = 0) {
    const letters = this.#console(id).cell.replace(/\d+$/, "")
    const index = [ ...letters ].reduce((sum, letter) => sum * 26 + letter.charCodeAt(0) - 64, 0) - 1
    return columnName(index + offset)
  }

  // Hours

  #config(id) {
    return this.configs[id]
  }

  #hoursOf(id, config = this.#config(id)) {
    const console = this.#console(id)
    const options = { ...Object.fromEntries(console.options.map((option) => [ option.id, option.default ])), ...config.options }
    const key = Object.keys(options).sort().map((option) => `${option}=${options[option]}`).join("|")
    return console.hours[key]
  }

  // The hours you've logged that you haven't spent: what's working towards the next thing.
  #unspent() {
    return Math.max(this.hoursValue - this.spentValue, 0)
  }

  #toGo(id) {
    return Math.max(Math.round((this.#hoursOf(id) - this.#unspent()) * 10) / 10, 0)
  }

  // locked (hours to go), unlocked (unspent logged hours cover it; ship, or ship again, so they're approved), ready
  // (what's left of your approved hours covers it: buy it) and shipping (bought). ShopHelper#shop_state.
  #stateOf(id) {
    if (this.ordersValue[id]) return "shipping"
    if (this.toSpendValue + 1e-6 >= this.#hoursOf(id)) return "ready"
    if (this.#unspent() + 1e-6 >= this.#hoursOf(id)) return "unlocked"
    return "locked"
  }

  #tagOf(id) {
    const state = this.#stateOf(id)
    if (state === "locked") return `${hrs(this.#toGo(id))} to go`
    if (state === "shipping") return CLAIMED_TAGS[this.ordersValue[id]]
    if (state === "unlocked" && this.shippedValue) return "ship again"
    return TAGS[state]
  }

  #colorOf(id) {
    const console = this.#console(id)
    return console.colors.find((color) => color.id === this.#config(id).color) ?? console.colors[0]
  }

  #choiceOf(id, option) {
    const picked = this.#config(id).options[option.id] ?? option.default
    return option.choices.find((choice) => choice.id === picked) ?? option.choices[0]
  }

  // "+7.5 hrs" against the option's default, with the tile's other choices as they are; "included" for nothing.
  #moreFor(id, option, choice) {
    const config = this.#config(id)
    const withIt = this.#hoursOf(id, { ...config, options: { ...config.options, [option.id]: choice.id } })
    const without = this.#hoursOf(id, { ...config, options: { ...config.options, [option.id]: option.default } })
    const difference = Math.round((withIt - without) * 10) / 10
    if (!difference) return "included"
    return `${difference > 0 ? "+" : "−"}${hrs(Math.abs(difference))} ${Math.abs(difference) === 1 ? "hr" : "hrs"}`
  }

  // "Transparent teal · 128 GB card": the colour, and any extra that isn't what it comes with.
  #variantOf(id) {
    const console = this.#console(id)
    const extras = console.options.map((option) => this.#choiceOf(id, option)).filter((choice, index) => choice.id !== console.options[index].default)
    return [ this.#colorOf(id).name, ...extras.map((choice) => lower(choice.name)) ].join(" · ")
  }

  // Moving about

  #select(id, { say = true } = {}) {
    if (!this.#console(id)) return
    this.selected = id
    this.talk = "main"
    this.marked = -1
    this.counterTarget.toggleAttribute("data-customizing", false)
    this.#render()
    this.tileTargets.find((tile) => tile.dataset.console === id)?.scrollIntoView({ block: "nearest", inline: "nearest", behavior: "smooth" })
    this.#fx(`=HANDHELD("${id}")  →  ${hrs(this.#hoursOf(id))} hrs`)
    if (say) this.#say(this.#lineFor(id))
  }

  #step(by) {
    const ids = this.#ids()
    const index = Math.min(Math.max(ids.indexOf(this.selected) + by, 0), ids.length - 1)
    if (ids[index] !== this.selected) this.#select(ids[index])
  }

  #mark(by) {
    const count = this.choicesTarget.children.length
    if (!count) return
    this.marked = (this.marked < 0 ? (by > 0 ? -1 : 0) : this.marked) + by
    this.marked = (this.marked + count) % count
    Array.from(this.choicesTarget.children).forEach((choice, index) => choice.toggleAttribute("data-marked", index === this.marked))
  }

  #talkTo(talk) {
    this.talk = talk
    this.marked = -1
    this.#renderChoices()
    this.counterTarget.toggleAttribute("data-customizing", talk === "color" || talk.startsWith("option:"))
    this.askTarget.hidden = talk !== "seller"
    if (talk === "seller") this.askInputTarget.focus()
  }

  // What Clippy says about the tile you've moved to.
  #lineFor(id) {
    const console = this.#console(id)
    const state = this.#stateOf(id)
    const cost = `${hrs(this.#hoursOf(id))} hours`
    if (state === "shipping") {
      return this.ordersValue[id] === "ordered" ? `${console.short}: yours, and it's ordered. :yay:` : `${console.short}: yours. someone will order it soon.`
    }
    if (id === this.pickValue) {
      if (state === "ready") return "this is your pick, and your approved hours cover it. buy it whenever you're ready. :yay:"
      if (state === "unlocked" && this.shippedValue) return "this is your pick. your hours cover it, so ship again and they'll count."
      if (state === "unlocked") return "this is your pick. your hours cover it, so ship your game and it's yours. :yay:"
      return `this is your pick. ${hrs(this.#toGo(id))} hours to go.`
    }
    if (state === "ready") return `${console.short}: ${cost}. you've ${hrs(this.toSpendValue)} approved to spend, so it's yours to buy. :yay:`
    if (state !== "locked") return `${console.short}: ${cost}. your hours cover it. :yay:`
    return `${console.short}: ${cost}. you've logged ${hrs(this.hoursValue)}.`
  }

  // The choices under what he says, for where the conversation is.
  #choices() {
    const id = this.selected
    const console = this.#console(id)
    const config = this.#config(id)
    const back = { icon: "back", label: "back", run: () => this.#talkTo("main") }

    if (this.talk === "color") {
      return [
        ...console.colors.map((color) => ({ swatch: color, label: color.name, on: color.id === config.color, run: () => this.#setColor(color.id, { back: true }) })),
        back
      ]
    }
    if (this.talk.startsWith("option:")) {
      const option = console.options.find((option) => option.id === this.talk.slice(7))
      return [
        ...option.choices.map((choice) => ({
          icon: ICON_FOR[option.id] ?? "extra", label: choice.name, more: this.#moreFor(id, option, choice),
          on: choice.id === this.#choiceOf(id, option).id, run: () => this.#setChoice(option.id, choice.id, { back: true })
        })),
        back
      ]
    }

    if (this.talk === "seller") return [ back ]
    if (this.talk === "address") return [ { icon: "send", tone: "pick", label: "share my address", run: () => this.addressFormTarget.requestSubmit() }, back ]
    if (this.talk === "claim") return [ { icon: "flag", tone: "pick", label: "yes, ship it to me", run: () => this.#claim() }, back ]

    const list = [ { icon: "info", label: `about the ${console.short}`, run: () => this.#about() } ]
    if (this.ordersValue[id]) return list
    if (console.colors.length > 1) list.push({ icon: "palette", label: `colour: ${this.#colorOf(id).name.toLowerCase()}`, run: () => this.#talkTo("color") })
    console.options.forEach((option) => {
      list.push({ icon: ICON_FOR[option.id] ?? "extra", label: lower(this.#choiceOf(id, option).name), run: () => this.#talkTo(`option:${option.id}`) })
    })
    const ask = this.#liveAsk(id)
    list.push({ icon: "store", label: ask ? `another seller: ${ask.label}` : "another seller, to save on customs", run: () => this.#askSeller() })
    if (this.#stateOf(id) === "ready") list.push({ icon: "flag", tone: "pick", label: "ship it to me", run: () => this.#confirmClaim() })
    else if (id !== this.pickValue) list.push({ icon: "flag", tone: "pick", label: "pick this one", run: () => this.#pick() })
    return list
  }

  // Buying the tile you're on, as it's set up: Clippy says what it costs and where it comes from first, since there's
  // no changing it after.
  #confirmClaim() {
    const id = this.selected
    const console = this.#console(id)
    const ask = this.#liveAsk(id)
    const from = ask?.status === "approved" ? ask.host : console.vendor
    if (this.needsAddressValue) {
      this.#talkTo("address")
      this.#say("we need your address to post it. share it through hack club, then come back and buy it.")
      return
    }
    this.#talkTo("claim")
    this.#say(`this isn't checkout. it's ${hrs(this.#hoursOf(id))} of your ${hrs(this.toSpendValue)} approved hours on the ${console.short} in ` +
              `${this.#colorOf(id).name.toLowerCase()}, from ${from}. once it's bought, it can't change.`)
  }

  async #claim() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    let data
    try {
      const id = this.selected
      const config = this.#config(id)
      const response = await fetch(this.claimUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ order: { prize: id, prize_color: config.color, prize_options: config.options } })
      })
      data = await response.json()
      if (!response.ok) throw new Error(data.error)
    } catch (error) {
      this.#say(lower(error.message || "that didn't go through. try again."))
      return
    }
    this.ordersValue = { ...this.ordersValue, [data.prize]: data.order }
    this.toSpendValue = data.hours_to_spend
    this.spentValue = data.hours_spent
    this.toSpendTarget.textContent = `${hrs(data.hours_to_spend)} hrs`
    this.sumTarget.textContent = data.sum
    this.#fx(data.formula)
    this.#talkTo("main")
    this.#render()
    const left = data.hours_to_spend > 0 ? ` ${hrs(data.hours_to_spend)} hours left to spend.` : " :yay:"
    this.#say(`${this.#console(data.prize).short} is bought. someone will order it soon.${left}`)
    this.clippy.congratulate(() => this.clippy.feel("happy"))
  }

  #askSeller() {
    const console = this.#console(this.selected)
    const ask = this.asks[this.selected]
    if (ask?.status === "pending") {
      this.#say(`your link to ${ask.host}'s in review. we'll let you know on slack.`)
      return
    }
    if (ask?.status === "approved") {
      this.#say(`${ask.host} is approved. if the ${console.short} is your pick, it'll come from there.`)
      return
    }
    this.#talkTo("seller")
    const before = ask?.status === "denied" ? `${ask.host} didn't work out. ` : ""
    this.#say(`${before}paste a link to the ${console.short} at a seller nearer you, so it gets to you without customs. same console, same spec. someone checks it.`)
  }

  #answer(index) {
    const choice = this.#choices()[index]
    if (!choice) return
    this.#finishTyping()
    choice.run()
  }

  #about() {
    const console = this.#console(this.selected)
    this.clippy.play("Explain")
    const deal = console.prize ? " one of the two we promised, so it's 10 hours as it comes." : ""
    this.#say(`${lower(console.blurb)} ${console.screen} screen, by ${console.maker}.${deal}`)
  }

  async #setColor(colorId, { back = false } = {}) {
    if (this.ordersValue[this.selected]) return // bought as it is
    const id = this.selected
    const console = this.#console(id)
    const color = console.colors.find((color) => color.id === colorId)
    if (!color) return
    this.#config(id).color = color.id
    this.#render()
    this.#fx(`=IMPORTRANGE("${console.site}", "Colour!${color.name}")`)
    if (back) this.#talkTo("main")
    this.#hop()
    if (id === this.pickValue) {
      if (await this.#save(id)) this.#say(`${color.name.toLowerCase()}. saved.`)
    } else {
      this.#say(`${color.name.toLowerCase()}. pick it and it comes like that.`)
    }
  }

  async #setChoice(optionId, choiceId, { back = false } = {}) {
    if (this.ordersValue[this.selected]) return // bought as it is
    const id = this.selected
    const console = this.#console(id)
    const option = console.options.find((option) => option.id === optionId)
    const choice = option?.choices.find((choice) => choice.id === choiceId)
    if (!choice) return
    this.#config(id).options = { ...this.#config(id).options, [option.id]: choice.id }
    this.#render()
    this.#fx(`=CUSTOMIZE("${console.short}", "${choice.name}")  →  ${this.#moreFor(id, option, choice)}`)
    if (back) this.#talkTo("main")
    this.#hop()
    const total = `${hrs(this.#hoursOf(id))} hours`
    if (id === this.pickValue) {
      if (await this.#save(id)) this.#say(`${lower(choice.name)}. that makes it ${total}. saved.`)
    } else {
      this.#say(`${lower(choice.name)}. that makes it ${total}, if you pick it.`)
    }
  }

  async #pick() {
    const id = this.selected
    const saved = await this.#save(id)
    if (!saved) return
    this.#fx(saved.formula)
    this.#hop()
    this.clippy.congratulate(() => this.clippy.feel(this.#stateOf(id) === "locked" ? "idle" : "happy"))
  }

  // Saving: the pick with its colour and extras. Clippy reads out what came back (or what went wrong), and
  // what came back is handed on (nothing if it didn't save).
  async #save(id) {
    const config = this.#config(id)
    const token = document.querySelector("meta[name='csrf-token']")?.content
    let data
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ project: { prize: id, prize_color: config.color, prize_options: config.options } })
      })
      data = await response.json()
      if (!response.ok) throw new Error(data.error)
    } catch (error) {
      this.#say(error.message || "that didn't save. try again.")
      return null
    }
    this.hoursValue = data.hours_logged
    this.configs[data.prize] = { color: data.prize_color, options: data.prize_options }
    this.pickValue = data.prize
    this.sumTarget.textContent = data.sum
    this.#say(data.says)
    this.#render()
    return data
  }

  // Drawing

  #render() {
    this.#renderTiles()
    this.#renderHeaders()
    this.#renderCustomize()
    this.#renderChoices()
  }

  #renderTiles() {
    this.tileTargets.forEach((tile) => {
      const id = tile.dataset.console
      const state = this.#stateOf(id)
      tile.dataset.state = state
      tile.toggleAttribute("data-yours", id === this.pickValue)
      tile.toggleAttribute("data-selected", id === this.selected)
      tile.querySelector("[data-shop-target='cost']").textContent = `${hrs(this.#hoursOf(id))} hrs`
      tile.querySelector("[data-shop-target='tag']").textContent = this.#tagOf(id)
      tile.querySelector("button").setAttribute("aria-pressed", id === this.pickValue)
    })
  }

  // The selection's columns and rows, and the name box.
  #renderHeaders() {
    const letters = [ 0, 1, 2 ].map((offset) => this.#column(this.selected, offset))
    this.columnHeaderTargets.forEach((header) => header.toggleAttribute("data-selected", letters.includes(header.dataset.column)))
    this.rowHeaderTargets.forEach((header) => {
      const row = Number(header.dataset.row)
      header.toggleAttribute("data-selected", row >= SHELF_ROW && row < SHELF_ROW + SHELF_ROWS)
    })
    this.nameBoxTarget.textContent = this.#console(this.selected).cell
  }

  #renderCustomize() {
    const id = this.selected
    const console = this.#console(id)
    this.customizeNameTarget.textContent = console.short
    this.variantTarget.textContent = this.#variantOf(id)
    this.swatchesTarget.replaceChildren(...console.colors.map((color) => {
      const button = element("button", { type: "button", class: "shop__swatch", title: color.name, "aria-label": color.name,
        "aria-pressed": color.id === this.#colorOf(id).id, "data-color": color.id, "data-action": "shop#pickColor" })
      button.style.setProperty("--swatch", color.hex)
      if (color.clear) button.setAttribute("data-clear", "")
      button.append(element("span", { class: "shop__swatch-dot" }))
      return button
    }))
    this.colorNameTarget.textContent = this.#colorOf(id).name
    this.optionsTarget.replaceChildren(...console.options.map((option) => {
      const row = element("div", { class: "shop__customize-row" })
      row.append(element("span", { class: "shop__customize-label" }, option.label))
      const chips = element("div", { class: "shop__chips" })
      option.choices.forEach((choice) => {
        const chip = element("button", { type: "button", class: "shop__chip", "aria-pressed": choice.id === this.#choiceOf(id, option).id,
          "data-option": option.id, "data-choice": choice.id, "data-action": "shop#pickChoice" }, choice.name)
        chip.append(element("span", { class: "shop__chip-more" }, this.#moreFor(id, option, choice)))
        chips.append(chip)
      })
      row.append(chips)
      return row
    }))
    const ask = this.#liveAsk(id)
    this.sellerTarget.textContent = ask ? `${ask.host} · ${ask.label}` : console.vendor
    this.sellerTarget.href = ask ? ask.url : console.url
    const extras = console.options.map((option) => this.#choiceOf(id, option).id)
    this.costFormulaTarget.textContent = `=HOURS(${[ `"${id}"`, ...extras.map((extra) => `"${extra}"`) ].join(", ")})`
    this.customizeCostTarget.textContent = `${hrs(this.#hoursOf(id))} hrs`
  }

  #renderChoices() {
    const choices = this.#choices()
    this.choicesTarget.dataset.columns = choices.length > 5 ? "2" : "1"
    this.choicesTarget.replaceChildren(...choices.map((choice, index) => {
      const button = element("button", { type: "button", class: "shop__choice", role: "option", "aria-selected": !!choice.on,
        "data-index": index, "data-action": "shop#choose" })
      button.append(element("span", { class: "shop__choice-mark" }, "▶"))
      if (choice.swatch) {
        const swatch = element("span", { class: "shop__choice-swatch" })
        swatch.style.setProperty("--swatch", choice.swatch.hex)
        if (choice.swatch.clear) swatch.setAttribute("data-clear", "")
        button.append(swatch)
      } else {
        button.append(icon(choice.icon, choice.tone))
      }
      button.append(element("span", { class: "shop__choice-label" }, choice.label))
      if (choice.more) button.append(element("span", { class: "shop__choice-more" }, choice.more))
      if (index === this.marked) button.setAttribute("data-marked", "")
      return button
    }))
  }

  #fx(text) {
    this.formulaTarget.textContent = text
  }

  #hop() {
    clearTimeout(this.hopTimer)
    this.mascotTarget.toggleAttribute("data-hop", true)
    this.hopTimer = setTimeout(() => this.mascotTarget.toggleAttribute("data-hop", false), 180)
  }

  // Typing it out, two characters a tick; click (or Escape) to have it all at once. An emote on the end
  // (":yay:") comes in as its picture once the words are there.
  #say(line) {
    clearInterval(this.typer)
    const { text, emotes } = splitEmotes(line)
    this.saying = { text, emotes }
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reduced) return this.#finishTyping()
    let shown = 0
    this.typedTarget.textContent = ""
    this.sayTarget.toggleAttribute("data-typing", true)
    this.typer = setInterval(() => {
      shown = Math.min(shown + 2, text.length)
      this.typedTarget.textContent = text.slice(0, shown)
      if (shown >= text.length) this.#finishTyping()
    }, 26)
  }

  #finishTyping() {
    clearInterval(this.typer)
    if (this.saying) {
      this.typedTarget.textContent = this.saying.text
      this.saying.emotes.forEach((name) => {
        const url = this.emotesValue[name]
        this.typedTarget.append(" ", url ? Object.assign(new Image(), { src: url, alt: `:${name}:`, title: name, className: "emote" }) : `:${name}:`)
      })
    }
    this.sayTarget.toggleAttribute("data-typing", false)
  }
}

const SHELF_ROW = 4
const SHELF_ROWS = 7
const CELL_WIDTH = 100

// A column's letters, the way a sheet names them, from 0: A … Z, AA, AB … (ShopHelper#column_name)
function columnName(index) {
  return index < 26 ? String.fromCharCode(65 + index) : columnName(Math.floor(index / 26) - 1) + columnName(index % 26)
}
const TAGS = { unlocked: "ship first", ready: "ready", closed: "" }
// Your pick's tag once it's claimed, by the order's status (ShopHelper::CLAIMED_TAGS).
const CLAIMED_TAGS = { waiting: "in the queue", ordered: "ordered" }
const ICON_FOR = { storage: "card" }

// The same icons as ShopHelper::ICONS.
const ICONS = {
  info: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 11v6M12 7.25v.5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  palette: '<path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-.9 2-2 0-.6-.3-1-.5-1.4-.3-.5-.5-.9-.5-1.6 0-1 .9-2 2-2h2a4 4 0 0 0 4-4c0-4-4-7-9-7Z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="7.5" cy="12" r="1.3"/><circle cx="10" cy="8" r="1.3"/><circle cx="14.5" cy="8" r="1.3"/><circle cx="17" cy="12" r="1.3"/>',
  card: '<path d="M8 3h10a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V8l3-5Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M10 7v3M13 7v3M16 7v3" stroke="currentColor" stroke-width="2"/>',
  extra: '<circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 8v8M8 12h8" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  flag: '<path d="M5 21V4h9l.5 2H20v9h-6.5l-.5-2H7v8H5Z"/>',
  back: '<path d="M14 6l-6 6 6 6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>',
  zoom: '<circle cx="10.5" cy="10.5" r="6.5" fill="none" stroke="currentColor" stroke-width="2"/><path d="M15.5 15.5 21 21M8 10.5h5M10.5 8v5" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
  store: '<path d="M4 10 5.5 4h13L20 10M4 10v10h16V10M4 10h16M9 20v-6h6v6" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
  send: '<path d="M4 12 20 4l-4 16-4-7-8-1Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/>',
}

// "your hours cover it. :yay:" → the words, and the emotes on the end.
function splitEmotes(line) {
  const emotes = []
  let text = line
  for (;;) {
    const match = text.match(/\s*:([a-z0-9_+-]+):\s*$/i)
    if (!match) break
    emotes.unshift(match[1])
    text = text.slice(0, match.index)
  }
  return { text, emotes }
}

// 12, or 13.3: hours without a trailing .0
function hrs(hours) {
  return String(Math.round(hours * 10) / 10)
}

// "128 GB card" → "128 GB card", "With a bag" → "with a bag": for the middle of a sentence.
function lower(text) {
  return text.replace(/^./, (letter) => letter.toLowerCase())
}

function element(tag, attributes = {}, text) {
  const node = document.createElement(tag)
  Object.entries(attributes).forEach(([ name, value ]) => node.setAttribute(name, value))
  if (text !== undefined) node.textContent = text
  return node
}

function icon(name, tone) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("class", "icon shop__choice-icon")
  svg.setAttribute("viewBox", "0 0 24 24")
  svg.setAttribute("aria-hidden", "true")
  if (tone) svg.setAttribute("data-tone", tone)
  svg.innerHTML = ICONS[name] ?? ICONS.info
  return svg
}
