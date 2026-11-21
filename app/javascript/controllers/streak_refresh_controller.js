import { Controller } from "@hotwired/stimulus"

// One turn of the arrow; keep in step with project-refresh-spin in project.css.
const TURN_MS = 800

// Refresh on your streak card: the button stays pressed while Hackatime's asked, and the arrow spins, with the
// refreshed page waiting for it to finish the turn it's on, so it always goes all the way round (at least once) and
// stops upright. With reduced motion, only the pressed look.
export default class extends Controller {
  spin() {
    this.element.toggleAttribute("data-refreshing", true)
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const startedAt = performance.now()
    this.element.toggleAttribute("data-spinning", true)
    this.holdRender = (event) => {
      event.preventDefault()
      setTimeout(event.detail.resume, TURN_MS - ((performance.now() - startedAt) % TURN_MS))
    }
    document.addEventListener("turbo:before-render", this.holdRender, { once: true })
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.holdRender)
  }
}
