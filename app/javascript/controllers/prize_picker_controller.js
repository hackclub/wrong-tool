import { Controller } from "@hotwired/stimulus"

const INTERVAL = 1280
const HANDHELDS = [ "rg35xx", "miyoo" ]

// Alternates which handheld is picked; the stylesheet does the highlighting.
// Holds still for reduced motion.
export default class extends Controller {
  static values = { pick: String }

  connect() {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.timer = setInterval(() => this.#next(), INTERVAL)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  #next() {
    if (this.element.closest("[hidden]")) return

    this.pickValue = HANDHELDS[(HANDHELDS.indexOf(this.pickValue) + 1) % HANDHELDS.length]
  }
}
