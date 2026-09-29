import { Controller } from "@hotwired/stimulus"

// A small sheet laid out with ordinary rows that grow to fit their text (the phone FAQ).
// Tapping a cell selects it and highlights its row and column; the name box and formula
// bar are the big sheet's, so the address and text are handed over with a "select" event.
export default class extends Controller {
  static targets = [ "cell", "row", "column" ]

  connect() {
    this.reset()
  }

  // Starts on the first cell, but only when this sheet is the one on screen.
  reset() {
    if (this.element.offsetParent) this.#select(this.cellTargets[0])
  }

  select(event) {
    const cell = this.cellTargets.find(target => target.contains(event.target))
    if (!cell) return

    event.stopPropagation() // keep the big sheet's selection out of it
    this.#select(cell)
  }

  #select(cell) {
    const columns = cell.dataset.columns.split(" ")

    this.cellTargets.forEach(target => target.toggleAttribute("data-selected", target === cell))
    this.rowTargets.forEach(row => row.toggleAttribute("data-selected", row.dataset.row === cell.dataset.row))
    this.columnTargets.forEach(column => column.toggleAttribute("data-selected", columns.includes(column.dataset.column)))

    this.dispatch("select", { detail: { address: `${columns[0]}${cell.dataset.row}`, formula: cell.textContent.trim().replace(/\s+/g, " ") } })
  }
}
