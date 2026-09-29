import { Controller } from "@hotwired/stimulus"
import { COLUMNS } from "sheet/formula"
import { address, boxOf, cellSize, zoomOf } from "sheet/grid"

const MOVES = { ArrowUp: [ 0, -1 ], ArrowDown: [ 0, 1 ], ArrowLeft: [ -1, 0 ], ArrowRight: [ 1, 0 ] }
const MAX_ROWS = 10000

// Spreadsheet-style selection: click a cell or move with the arrow keys, and select
// ranges as in Sheets: Shift+arrows, Shift+click, dragging, the column and row headers,
// the corner or Ctrl+A. Ctrl+arrows jump to the edge of the data. The active cell, the
// range, the headers, the name box and the formula bar follow along, and a "select"
// event tells the sheet editor what's selected.
export default class extends Controller {
  static targets = [ "grid", "selection", "range", "columnHeader", "rowHeader", "nameBox", "nameInput", "formula", "initial" ]

  connect() {
    this.selectionTarget.hidden = false
    this.rangeTarget.hidden = false
    this.cellWidth = cellSize(this.gridTarget).width
    this.drag = this.drag.bind(this)
    this.release = this.release.bind(this)
    this.reset()
  }

  disconnect() {
    this.release()
  }

  // Selects the section's marked starting cell, or its first cell.
  reset() {
    const start = this.initialTargets.find(cell => this.#section.contains(cell) && cell.offsetParent) ?? this.#cells[0]
    this.#select(start ? this.#boxOf(start) : { column: 0, row: 0 })
  }

  // Re-reads the selected cell, for when its contents change underneath the selection.
  // A range stays selected, grown to cover the active cell if that's been merged.
  refresh() {
    if (!this.box) return

    const range = this.#single ? null : this.range
    this.#select(this.box, range)
  }

  // Shows a cell picked somewhere else, like the phone FAQ's mini-sheet.
  show({ detail: { address, formula } }) {
    this.nameBoxTarget.textContent = address
    this.formulaTarget.textContent = formula
  }

  // The grid switches between desktop and phone cell sizes at the breakpoint.
  relayout() {
    const { width } = cellSize(this.gridTarget)
    if (width === this.cellWidth) return

    this.cellWidth = width
    this.reset()
  }

  // Commands from the toolbar and menus. The rest are the sheet editor's.
  command({ detail: { command, value } }) {
    if (command === "selectAll") {
      this.#selectAll()
    } else if (command === "goTo") {
      this.#goTo(value)
    } else {
      return
    }
    this.gridTarget.focus({ preventScroll: true })
  }

  // Pressing on a cell selects it (Shift extends the range), and dragging selects a range.
  press(event) {
    if (event.button !== 0 || this.#ignored(event.target)) return

    event.preventDefault() // no text selection, no dragging links and images around
    this.pressed = true
    if (event.shiftKey) {
      this.#extend(this.#pointer(event))
    } else {
      this.#select(this.#pointer(event))
    }
    this.gridTarget.focus({ preventScroll: true })
    this.#startDrag("cells")
  }

  // A click the press above didn't see first (a tap, or one dispatched by a script).
  click(event) {
    if (this.pressed) {
      this.pressed = false
      return
    }
    if (this.#ignored(event.target)) return

    if (event.shiftKey) {
      this.#extend(this.#pointer(event))
    } else {
      this.#select(this.#pointer(event))
    }
    this.gridTarget.focus({ preventScroll: true })
  }

  // The column and row headers select whole columns and rows; the corner selects everything.
  pressHeader(event) {
    if (event.button !== 0) return

    event.preventDefault()
    this.gridTarget.focus({ preventScroll: true })
    if (event.target.closest(".sheet__corner")) return this.#selectAll()

    const column = this.columnHeaderTargets.indexOf(event.target.closest("[data-cell-selection-target=columnHeader]"))
    const row = this.rowHeaderTargets.indexOf(event.target.closest("[data-cell-selection-target=rowHeader]"))
    const kind = column >= 0 ? "columns" : row >= 0 ? "rows" : null
    if (!kind) return

    const index = kind === "columns" ? column : row
    if (event.shiftKey && this.box) {
      this.lineAnchor = kind === "columns" ? this.box.column : this.box.row
      this.#selectLines(kind, this.lineAnchor, index, { keep: true })
    } else {
      this.lineAnchor = index
      this.#selectLines(kind, index, index)
    }
    this.#startDrag(kind)
  }

  // Follows the mouse while a press is held.
  drag(event) {
    if (!(event.buttons & 1)) return this.release()

    const { column, row } = this.#pointer(event)
    if (this.dragging === "cells") this.#extend({ column, row })
    else if (this.dragging === "columns") this.#selectLines("columns", this.lineAnchor, column, { keep: true })
    else if (this.dragging === "rows") this.#selectLines("rows", this.lineAnchor, row, { keep: true })
  }

  release() {
    this.dragging = null
    window.removeEventListener("mousemove", this.drag)
    window.removeEventListener("mouseup", this.release)
  }

  // Arrows move; Shift grows or shrinks the range; Ctrl/Cmd jumps to the edge of the data.
  move(event) {
    const jump = event.ctrlKey || event.metaKey

    if (jump && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "a") {
      event.preventDefault()
      return this.#selectAll()
    }
    if (event.key === "Home") {
      event.preventDefault()
      return this.#select(jump ? { column: 0, row: 0 } : { column: 0, row: this.box.row }, null, { reveal: true })
    }

    const move = MOVES[event.key]
    if (!move) return

    event.preventDefault()
    if (event.shiftKey) this.#resize(move, jump)
    else if (jump) this.#select(this.#jump(this.box, move), null, { reveal: true })
    else this.#step(move)
  }

  // Moves on from a cell the sheet editor has just filled in (down after Enter, across after Tab).
  step({ detail: { key } }) {
    this.#step(MOVES[key])
  }

  // Clicking the name box turns it into a field: type an address or a range and press Enter.
  name(event) {
    event.stopPropagation() // it's not the formula bar's to edit the cell with
    if (!this.nameInputTarget.hidden) return

    this.nameInputTarget.value = this.nameBoxTarget.textContent
    this.nameBoxTarget.hidden = true
    this.nameInputTarget.hidden = false
    this.nameInputTarget.focus()
    this.nameInputTarget.select()
  }

  nameKey(event) {
    event.stopPropagation()
    if (event.key === "Enter") {
      event.preventDefault()
      if (this.#goTo(this.nameInputTarget.value)) {
        this.#closeName()
        this.gridTarget.focus({ preventScroll: true })
      } else {
        this.nameInputTarget.select()
      }
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.#closeName()
      this.gridTarget.focus({ preventScroll: true })
    }
  }

  closeName() {
    this.#closeName()
  }

  #closeName() {
    this.nameInputTarget.hidden = true
    this.nameBoxTarget.hidden = false
  }

  // Step off the edge of the selected box, so merged cells are crossed in one move.
  #step(move) {
    const { column, row, width, height } = this.box
    this.#select({
      column: clamp(move[0] > 0 ? column + width : column + move[0], 0, this.#columnCount - 1),
      row: clamp(move[1] > 0 ? row + height : row + move[1], 0, this.#rowCount - 1)
    })
    this.selectionTarget.scrollIntoView({ block: "nearest", inline: "nearest" })
  }

  // Shift+arrows move the range's free edge (the one away from the active cell) by a
  // cell, or with Ctrl/Cmd to the edge of the data, like Sheets.
  #resize(move, jump) {
    const boxes = this.#boxes()
    const axis = move[0] ? "column" : "row"
    const size = axis === "column" ? "width" : "height"
    const direction = move[0] || move[1]
    const anchor = this.box
    let range = this.range

    // Shrinking can land inside a merged cell and grow straight back, so keep going until it changes.
    for (let tries = 0; tries < 100; tries++) {
      const low = range[axis]
      const high = range[axis] + range[size] - 1
      const anchorLow = anchor[axis]
      const anchorHigh = anchor[axis] + anchor[size] - 1
      const edge = direction > 0 ? (low < anchorLow ? low : high) : (high > anchorHigh ? high : low)

      const from = { ...anchor, [axis]: edge, [size]: 1 }
      const target = jump ? this.#jump(from, move, boxes)[axis] : clamp(edge + direction, 0, this.#limit(axis))
      const next = this.#expand({
        ...range,
        [axis]: Math.min(anchorLow, target),
        [size]: Math.max(anchorHigh, target) - Math.min(anchorLow, target) + 1
      }, boxes)

      if (!sameBox(next, range) || target === edge) {
        range = next
        break
      }
      range = { ...range, [axis]: Math.min(anchorLow, target), [size]: Math.max(anchorHigh, target) - Math.min(anchorLow, target) + 1 }
    }

    this.range = range
    this.#render()
    this.#reveal(this.#freeCorner(range))
  }

  // Ctrl/Cmd+arrow, as in Sheets: from a filled cell to the last filled one before a gap;
  // from an empty cell (or the edge of a run) to the next filled one, or the sheet's edge.
  #jump(box, move, boxes = this.#boxes()) {
    const filled = position => Boolean(this.#cellAt(position, boxes))
    const next = position => {
      const covering = this.#cellAt(position, boxes)
      const current = covering ? boxOfCell(boxes, covering) : { ...position, width: 1, height: 1 }
      const column = move[0] > 0 ? current.column + current.width : move[0] < 0 ? current.column - 1 : position.column
      const row = move[1] > 0 ? current.row + current.height : move[1] < 0 ? current.row - 1 : position.row
      if (column < 0 || row < 0 || column >= this.#columnCount || row >= this.#rowCount) return null
      return { column, row }
    }

    let position = { column: box.column, row: box.row }
    let ahead = next(position)
    if (!ahead) return position

    if (filled(position) && filled(ahead)) {
      while (ahead && filled(ahead)) {
        position = ahead
        ahead = next(position)
      }
      return position
    }

    position = ahead
    while (!filled(position)) {
      ahead = next(position)
      if (!ahead) break
      position = ahead
    }
    return position
  }

  #selectAll() {
    this.#select({ column: 0, row: 0 }, { column: 0, row: 0, width: this.#columnCount, height: this.#rowCount })
  }

  // Whole columns or rows, from one header to another. The active cell is the first one's top (or left) cell.
  #selectLines(kind, from, to, { keep = false } = {}) {
    const low = Math.min(from, to)
    const count = Math.abs(to - from) + 1
    const range = kind === "columns" ?
      { column: low, row: 0, width: count, height: this.#rowCount } :
      { column: 0, row: low, width: this.#columnCount, height: count }

    if (keep && this.box && this.#inside(this.box, range)) {
      this.range = range
      this.#render()
    } else {
      this.#select(kind === "columns" ? { column: from, row: 0 } : { column: 0, row: from }, range)
    }
  }

  // "B12", "B2:D5", "B:D" or "3:5" (the name box, and the goTo command).
  #goTo(text) {
    const range = this.#parse(text ?? "")
    if (!range) return false

    this.#select({ column: range.column, row: range.row }, range.width * range.height > 1 ? range : null, { reveal: true })
    return true
  }

  #parse(text) {
    const value = text.trim().toUpperCase().replaceAll("$", "")
    const column = letter => COLUMNS.indexOf(letter)
    const row = number => clamp(Number(number) - 1, 0, MAX_ROWS - 1)
    let match

    if ((match = value.match(/^([A-Z])(\d+)(?::([A-Z])(\d+))?$/)) && Number(match[2]) > 0) {
      const start = { column: column(match[1]), row: row(match[2]) }
      const end = match[3] ? { column: column(match[3]), row: row(match[4]) } : start
      return bounding({ ...start, width: 1, height: 1 }, { ...end, width: 1, height: 1 })
    }
    if ((match = value.match(/^([A-Z]):([A-Z])$/))) {
      const [ low, high ] = [ column(match[1]), column(match[2]) ].sort((a, b) => a - b)
      return { column: low, row: 0, width: high - low + 1, height: this.#rowCount }
    }
    if ((match = value.match(/^(\d+):(\d+)$/)) && Number(match[1]) > 0 && Number(match[2]) > 0) {
      const [ low, high ] = [ row(match[1]), row(match[2]) ].sort((a, b) => a - b)
      return { column: 0, row: low, width: this.#columnCount, height: high - low + 1 }
    }
  }

  // Makes a position the active cell. The range is just that cell unless one's given.
  #select(position, range = null, { reveal = false } = {}) {
    const boxes = this.#boxes()
    const cell = this.#cellAt(position, boxes)
    const box = cell ? boxOfCell(boxes, cell) : { column: position.column, row: position.row, width: 1, height: 1 }

    this.box = box
    this.cell = cell
    this.range = range ? (this.#full(range) ? bounding(range, box) : this.#expand(bounding(range, box), boxes)) : box
    this.#render()
    if (reveal) this.#reveal(box)
  }

  // Keeps the active cell and stretches the range from it to a position.
  #extend(position) {
    if (!this.box) return this.#select(position)

    const range = this.#expand(bounding(this.box, { ...position, width: 1, height: 1 }))
    if (sameBox(range, this.range)) return

    this.range = range
    this.#render()
  }

  #render() {
    const { box, cell, range } = this

    this.#place(this.selectionTarget, box)
    this.#place(this.rangeTarget, range)
    this.#drawHole(box, range)
    this.selectionTarget.classList.toggle("sheet__selection--in-range", !this.#single)
    this.rangeTarget.classList.toggle("sheet__range--single", this.#single)
    this.#highlightHeaders(range)
    this.nameBoxTarget.textContent = this.#rangeName
    this.formulaTarget.textContent = cell ? cell.dataset.formula ?? cell.textContent.trim() : ""
    this.dispatch("select", { detail: { box, cell, range: { ...range } } })
  }

  #place(element, { column, row, width, height }) {
    const style = element.style
    style.setProperty("--column", column + 1)
    style.setProperty("--row", row + 1)
    style.setProperty("--width", width)
    style.setProperty("--height", height)
  }

  // The active cell shows through the range's tint, as in Sheets.
  #drawHole(box, range) {
    const style = this.rangeTarget.style
    style.setProperty("--hole-column", box.column - range.column)
    style.setProperty("--hole-row", box.row - range.row)
    style.setProperty("--hole-width", box.width)
    style.setProperty("--hole-height", box.height)
  }

  #highlightHeaders({ column, row, width, height }) {
    const fullColumns = row === 0 && height >= this.#rowCount
    const fullRows = column === 0 && width >= this.#columnCount

    this.columnHeaderTargets.forEach((header, index) => {
      const selected = index >= column && index < column + width
      header.classList.toggle("sheet__column-header--selected", selected)
      header.classList.toggle("sheet__column-header--full", selected && fullColumns)
    })
    this.rowHeaderTargets.forEach((header, index) => {
      const selected = index >= row && index < row + height
      header.classList.toggle("sheet__row-header--selected", selected)
      header.classList.toggle("sheet__row-header--full", selected && fullRows)
    })
  }

  // "B6" for a cell (merged or not), "B2:D5" for a range, "B:D" and "3:5" for whole columns and rows.
  get #rangeName() {
    const { column, row, width, height } = this.range
    const fullColumns = row === 0 && height >= this.#rowCount
    const fullRows = column === 0 && width >= this.#columnCount

    if (this.#single) return address(this.box)
    if (fullColumns && !fullRows) return `${COLUMNS[column]}:${COLUMNS[column + width - 1]}`
    if (fullRows && !fullColumns) return `${row + 1}:${row + height}`
    return `${address(this.range)}:${address({ column: column + width - 1, row: row + height - 1 })}`
  }

  get #single() {
    return !this.range || sameBox(this.range, this.box)
  }

  #full(range) {
    return (range.row === 0 && range.height >= this.#rowCount) || (range.column === 0 && range.width >= this.#columnCount)
  }

  #inside(box, range) {
    return box.column >= range.column && box.column + box.width <= range.column + range.width &&
      box.row >= range.row && box.row + box.height <= range.row + range.height
  }

  // Grows a range until no merged cell sticks out of it.
  #expand(range, boxes = this.#boxes()) {
    let grown = range
    let changed = true
    while (changed) {
      changed = false
      for (const { box } of boxes) {
        if (overlaps(grown, box) && !this.#inside(box, grown)) {
          grown = bounding(grown, box)
          changed = true
        }
      }
    }
    return grown
  }

  // The corner of the range away from the active cell, to keep in view as it grows.
  #freeCorner(range) {
    const column = range.column < this.box.column ? range.column : range.column + range.width - 1
    const row = range.row < this.box.row ? range.row : range.row + range.height - 1
    return { column, row, width: 1, height: 1 }
  }

  // Scrolls just enough to show a box, clear of the sticky headers.
  #reveal({ column, row, width = 1, height = 1 }) {
    const viewport = this.gridTarget.closest(".sheet-viewport")
    if (!viewport) return

    // In screen pixels, so scaled by the zoom.
    const zoom = zoomOf(this.gridTarget)
    const { width: cellWidth, height: cellHeight } = cellSize(this.gridTarget)
    const size = { width: cellWidth * zoom, height: cellHeight * zoom }
    const grid = this.gridTarget.getBoundingClientRect()
    const view = viewport.getBoundingClientRect()
    const style = getComputedStyle(this.gridTarget)
    const headerWidth = (parseFloat(style.getPropertyValue("--row-header-width")) || 0) * zoom
    const headerHeight = (parseFloat(style.getPropertyValue("--column-header-height")) || 0) * zoom

    const left = grid.left + column * size.width
    const top = grid.top + row * size.height
    const right = left + Math.min(width * size.width, viewport.clientWidth - headerWidth)
    const bottom = top + Math.min(height * size.height, viewport.clientHeight - headerHeight)

    if (left < view.left + headerWidth) viewport.scrollLeft -= view.left + headerWidth - left
    else if (right > view.left + viewport.clientWidth) viewport.scrollLeft += right - view.left - viewport.clientWidth
    if (top < view.top + headerHeight) viewport.scrollTop -= view.top + headerHeight - top
    else if (bottom > view.top + viewport.clientHeight) viewport.scrollTop += bottom - view.top - viewport.clientHeight
  }

  #startDrag(kind) {
    this.dragging = kind
    window.addEventListener("mousemove", this.drag)
    window.addEventListener("mouseup", this.release)
  }

  #pointer(event) {
    const { left, top } = this.gridTarget.getBoundingClientRect()
    const { width, height } = cellSize(this.gridTarget)
    const zoom = zoomOf(this.gridTarget)
    return {
      column: clamp(Math.floor((event.clientX - left) / zoom / width), 0, this.#columnCount - 1),
      row: clamp(Math.floor((event.clientY - top) / zoom / height), 0, this.#rowCount - 1)
    }
  }

  // The cell editor and the phone FAQ's mini-sheet handle their own clicks.
  #ignored(target) {
    return target.closest(".sheet__editor, [data-controller~=mini-sheet]")
  }

  #limit(axis) {
    return (axis === "column" ? this.#columnCount : this.#rowCount) - 1
  }

  get #columnCount() {
    return this.columnHeaderTargets.length
  }

  get #rowCount() {
    return this.rowHeaderTargets.length
  }

  // The topmost cell covering a position, if any.
  #cellAt({ column, row }, boxes = this.#boxes()) {
    for (let index = boxes.length - 1; index >= 0; index--) {
      const { box, cell } = boxes[index]
      if (column >= box.column && column < box.column + box.width && row >= box.row && row < box.row + box.height) return cell
    }
  }

  // Every cell on screen with the columns and rows it covers, read once per change.
  #boxes() {
    const size = cellSize(this.gridTarget)
    return this.#cells.map(cell => ({ cell, box: boxOf(cell, size) }))
  }

  #boxOf(cell) {
    return boxOf(cell, cellSize(this.gridTarget))
  }

  // Cells laid out in the open section, skipping any hidden at this size, then the ones typed in.
  get #cells() {
    const cells = this.gridTarget.querySelectorAll(".sheet__section:not([hidden]) .cell, .sheet__entries .cell")
    return [ ...cells ].filter(cell => cell.offsetParent)
  }

  get #section() {
    return this.gridTarget.querySelector(".sheet__section:not([hidden])")
  }
}

function boxOfCell(boxes, cell) {
  return boxes.find(entry => entry.cell === cell).box
}

function bounding(a, b) {
  const column = Math.min(a.column, b.column)
  const row = Math.min(a.row, b.row)
  return {
    column,
    row,
    width: Math.max(a.column + a.width, b.column + b.width) - column,
    height: Math.max(a.row + a.height, b.row + b.height) - row
  }
}

function overlaps(a, b) {
  return a.column < b.column + b.width && b.column < a.column + a.width &&
    a.row < b.row + b.height && b.row < a.row + a.height
}

function sameBox(a, b) {
  return a.column === b.column && a.row === b.row && a.width === b.width && a.height === b.height
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}
