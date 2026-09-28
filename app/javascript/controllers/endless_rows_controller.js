import { Controller } from "@hotwired/stimulus"

const BATCH = 50

// Rows never run out: keep at least a screenful of rows below the fold,
// adding more row headers as the sheet scrolls. The grid stretches to match.
export default class extends Controller {
  static targets = [ "headers", "template" ]

  connect() {
    this.fill()
  }

  fill() {
    const { scrollTop, clientHeight, scrollHeight } = this.element
    if (clientHeight === 0 || scrollTop + clientHeight * 2 < scrollHeight) return

    this.#addRows()
    this.fill()
  }

  #addRows() {
    const rows = document.createDocumentFragment()
    const start = this.headersTarget.children.length

    for (let number = start + 1; number <= start + BATCH; number++) {
      const header = this.templateTarget.content.firstElementChild.cloneNode()
      header.textContent = number
      rows.append(header)
    }
    this.headersTarget.append(rows)
  }
}
