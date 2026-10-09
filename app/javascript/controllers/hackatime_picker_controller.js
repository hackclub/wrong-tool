import { Controller } from "@hotwired/stimulus"

// The Hackatime projects dropdown: as you tick projects, the closed field lists them and the button says how many
// it'll link ("Tick a project above" and greyed out with none). Clicking elsewhere closes it.
export default class extends Controller {
  static targets = [ "dropdown", "summary", "submit" ]

  update() {
    const names = Array.from(this.element.querySelectorAll("input[type=checkbox]:checked"), (box) => box.value)
    this.summaryTarget.textContent = names.join(", ") || this.summaryTarget.dataset.placeholder
    this.submitTarget.disabled = names.length === 0
    this.submitTarget.textContent = names.length === 0 ? "Tick a project above"
      : names.length === 1 ? "Link project" : `Link ${names.length} projects`
  }

  close(event) {
    if (!this.dropdownTarget.contains(event.target)) this.dropdownTarget.open = false
  }
}
