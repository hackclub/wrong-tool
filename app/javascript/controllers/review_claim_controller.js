import { Controller } from "@hotwired/stimulus"

// A ship's review page, while it's yours (ReviewClaim): tells the server you're still on it every so often, so the
// claim doesn't go idle. Once it's someone else's (an admin took over, or it went idle and someone opened it), the
// page reloads to say so.
export default class extends Controller {
  static values = { url: String, every: Number }

  connect() {
    this.timer = setInterval(() => this.beat(), this.everyValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async beat() {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.urlValue, { method: "PATCH", headers: { "X-CSRF-Token": token } }).catch(() => null)
    if (response?.status === 409) {
      clearInterval(this.timer)
      location.reload()
    }
  }
}
