import { Controller } from "@hotwired/stimulus"
import { capture, previewing } from "analytics"

// What people do on the landing page, for PostHog: which sections (sheet tabs) they open, how long they stay on
// each and how far down it they get, and what they play with there. (Clicks and pageviews are autocaptured.)
// A section's time only counts while the page is showing, so a hidden tab sends what it had and starts again.
export default class extends Controller {
  static targets = [ "viewport", "section" ]

  connect() {
    if (previewing()) return
    this.#enter("landing")
    this.onVisibility = () => document.hidden ? this.#leave() : this.#enter("return")
    addEventListener("visibilitychange", this.onVisibility)
  }

  disconnect() {
    removeEventListener("visibilitychange", this.onVisibility)
    this.#leave()
  }

  // sheet-tabs:change
  changeSection() {
    if (this.#openSection() === this.section) return
    this.#leave()
    this.#enter("tab")
  }

  scroll() {
    this.furthest = Math.max(this.furthest, this.#seenPercent())
  }

  // toolbar:command and menu-bar:command: someone's editing the sheet.
  command({ type, detail: { command, value } }) {
    capture("landing_command", { ...this.#where(), source: type.split(":")[0], command,
                                 value: typeof value === "object" ? undefined : value })
  }

  // flap-game:change, as a game starts (or a pipe's passed): it counts once a visit.
  play() {
    if (this.played) return
    this.played = true
    capture("landing_game_played", this.#where())
  }

  // idea-roulette:change
  rollIdea() {
    capture("landing_idea_rolled", this.#where())
  }

  // mini-sheet:select, a question (or answer) in the phone FAQ.
  selectFaq({ detail: { address, formula } }) {
    capture("landing_faq_selected", { ...this.#where(), cell: address, text: formula.slice(0, 200) })
  }

  // A press on the grid (the selection also moves by itself, so its select events won't do).
  pressCell() {
    this.cells++
  }

  #enter(via) {
    if (this.enteredAt != null) return
    const section = this.#openSection()
    if (!section) return
    if (via !== "return") capture("landing_section_viewed", { section: section.id, via })
    Object.assign(this, { section, enteredAt: performance.now(), cells: 0 })
    this.furthest = this.#seenPercent()
  }

  // The section's time, how far down it they got and how many cells they pressed. It may be the last thing the
  // page sends, so it goes as a beacon.
  #leave() {
    if (this.enteredAt == null) return
    capture("landing_section_read", {
      section: this.section.id, seconds: Math.round((performance.now() - this.enteredAt) / 1000),
      max_scroll_percent: this.furthest, cells_clicked: this.cells
    }, { transport: "sendBeacon" })
    this.enteredAt = null
  }

  #where() {
    return { section: this.#openSection()?.id }
  }

  #openSection() {
    return this.sectionTargets.find(section => !section.hidden)
  }

  // How much of the open section has been on screen, down to the bottom of its footer. (Sections span rows of
  // empty grid below that, and the rows go on forever, so neither they nor the viewport say where it ends.)
  #seenPercent() {
    const section = this.#openSection()
    if (!section || !this.hasViewportTarget) return 0
    const { top } = section.getBoundingClientRect()
    const height = (section.lastElementChild ?? section).getBoundingClientRect().bottom - top
    const seen = this.viewportTarget.getBoundingClientRect().bottom - top
    return height > 0 ? Math.round(100 * Math.min(1, Math.max(0, seen / height))) : 100
  }
}
