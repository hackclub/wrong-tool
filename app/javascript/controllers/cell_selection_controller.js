import { Controller } from "@hotwired/stimulus"

const COLUMNS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const MOVES = { ArrowUp: [ 0, -1 ], ArrowDown: [ 0, 1 ], ArrowLeft: [ -1, 0 ], ArrowRight: [ 1, 0 ] }

// Spreadsheet-style selection: click a cell or move with the arrow keys. The
// selection box, the headers, the name box and the formula bar follow along.
// Cell positions are read from the layout, so the CSS stays the single source.
export default class extends Controller {
  static targets = [ "grid", "selection", "columnHeader", "rowHeader", "nameBox", "formula", "initial" ]

  connect() {
    this.selectionTarget.hidden = false
    this.reset()
  }

  // Selects the section's marked starting cell, or B2.
  reset() {
    const initial = this.initialTargets.find(cell => this.#section.contains(cell))
    this.#select(initial ? this.#boxOf(initial) : { column: 1, row: 1 })
  }

  // Re-reads the selected cell, for when its contents change underneath the selection.
  refresh() {
    if (this.box) this.#select(this.box)
  }

  click(event) {
    const { left, top } = this.gridTarget.getBoundingClientRect()
    const { width, height } = this.#cellSize
    const position = {
      column: Math.floor((event.clientX - left) / width),
      row: Math.floor((event.clientY - top) / height)
    }
    const cell = this.#cellAt(position)

    this.#select(cell ? this.#boxOf(cell) : position)
    // Let input cells keep focus so they can be typed into.
    if (!event.target.matches("input")) this.gridTarget.focus({ preventScroll: true })
  }

  move(event) {
    const move = MOVES[event.key]
    if (!move || event.target.matches("input")) return

    // Step off the edge of the selected box, so merged cells are crossed in one move.
    const { column, row, width, height } = this.box
    event.preventDefault()
    this.#select({
      column: clamp(move[0] > 0 ? column + width : column + move[0], 0, this.columnHeaderTargets.length - 1),
      row: clamp(move[1] > 0 ? row + height : row + move[1], 0, this.rowHeaderTargets.length - 1)
    })
    this.selectionTarget.scrollIntoView({ block: "nearest", inline: "nearest" })
  }

  #select(position) {
    const cell = this.#cellAt(position)
    const box = cell ? this.#boxOf(cell) : { ...position, width: 1, height: 1 }

    this.box = box
    this.#drawSelection(box)
    this.#highlightHeaders(box)
    this.#showNote(cell)
    this.nameBoxTarget.textContent = `${COLUMNS[box.column]}${box.row + 1}`
    this.formulaTarget.textContent = cell ? this.#formulaOf(cell) : ""
  }

  #formulaOf(cell) {
    return cell.dataset.formula ?? cell.querySelector("input")?.value ?? cell.textContent.trim()
  }

  #drawSelection({ column, row, width, height }) {
    const style = this.selectionTarget.style
    style.setProperty("--column", column + 1)
    style.setProperty("--row", row + 1)
    style.setProperty("--width", width)
    style.setProperty("--height", height)
  }

  #highlightHeaders({ column, row, width, height }) {
    this.columnHeaderTargets.forEach((header, index) => {
      header.classList.toggle("sheet__column-header--selected", index >= column && index < column + width)
    })
    this.rowHeaderTargets.forEach((header, index) => {
      header.classList.toggle("sheet__row-header--selected", index >= row && index < row + height)
    })
  }

  // A cell can point at a hidden note with aria-describedby; it shows while the cell is selected.
  #showNote(cell) {
    const noteId = cell?.getAttribute("aria-describedby")
    this.#section.querySelectorAll(".cell--note").forEach(note => note.hidden = note.id !== noteId)
  }

  // The topmost cell covering a position, if any. Anything with a formula counts as a cell.
  #cellAt({ column, row }) {
    const cells = [ ...this.#section.querySelectorAll(".cell:not(.cell--note), [data-formula]") ]
    return cells.reverse().find(cell => {
      const box = this.#boxOf(cell)
      return column >= box.column && column < box.column + box.width &&
        row >= box.row && row < box.row + box.height
    })
  }

  // Cells stop 1px short of their gridlines, hence the rounding.
  #boxOf(cell) {
    const { width, height } = this.#cellSize
    return {
      column: Math.round(cell.offsetLeft / width),
      row: Math.round(cell.offsetTop / height),
      width: Math.round(cell.offsetWidth / width),
      height: Math.round(cell.offsetHeight / height)
    }
  }

  get #cellSize() {
    const style = getComputedStyle(this.gridTarget)
    return {
      width: parseFloat(style.getPropertyValue("--cell-width")),
      height: parseFloat(style.getPropertyValue("--cell-height"))
    }
  }

  get #section() {
    return this.gridTarget.querySelector(".sheet__section:not([hidden])")
  }
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}
