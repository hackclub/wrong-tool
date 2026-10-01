import { Controller } from "@hotwired/stimulus"

const KEY = "wrong-tool:sidebar-open"

// The sidebar's folding cards: keeps whichever you last opened open when the page comes back (after adding to the
// queue, say), unless the server opened one that needs you.
export default class extends Controller {
  static values = { urgent: Boolean }

  connect() {
    this.remember = (event) => {
      if (event.target.open) write(KEY, event.target.dataset.section)
    }
    this.element.addEventListener("toggle", this.remember, true)

    const saved = read(KEY)
    const section = !this.urgentValue && saved && this.element.querySelector(`[data-section="${saved}"]`)
    if (section) section.open = true
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.remember, true)
  }
}

// localStorage can be off (private windows, blocked storage); then it just doesn't remember.
function read(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function write(key, value) {
  try { localStorage.setItem(key, value) } catch {}
}
