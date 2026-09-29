import { Controller } from "@hotwired/stimulus"
import { SheetError, evaluate, literal, shift } from "sheet/formula"
import { decimalsShown, formatValue, impliedByFormula, interpret, kind } from "sheet/format"
import { address, boxOf, cellSize, position, zoomOf } from "sheet/grid"

const STORAGE_KEY = "wrong-tool:sheet:"
const OLD_STORAGE_KEY = "wrong-tool:entries:"
const HISTORY = 100
const BORDER = "var(--text-primary)"
const NUMBER_SHORTCUTS = { Digit1: "number", Digit2: "time", Digit3: "date", Digit4: "currency", Digit5: "percent", Digit6: "scientific" }
const ALIGN_SHORTCUTS = { KeyL: "left", KeyE: "center", KeyR: "right" }
const TOGGLES = [ "bold", "italic", "underline", "strikethrough" ]

// Editing the sheet, as in Sheets. Every cell takes values, formulas and formatting:
// empty cells, and the landing page's own cells too. Each tab keeps its cells in
// localStorage as { cells: { key: { value, format, merge, note } } }, keyed by address
// ("A25") for the empty grid, and "#n" for the n-th of the page's own cells.
//
// Cells typed into the empty grid are drawn into .sheet__entries. A page cell that's
// typed over is hidden (never removed: other controllers keep targets inside it) behind
// a "shell" that takes its classes and style, so it looks and sits the same. Clearing
// the cell's value brings the page's own cell back.
//
// Typing, Enter, F2 or a double-click opens the editor on the selected cell, and so does
// the formula bar. Enter and Tab save and move on, Escape cancels, Delete clears.
// Formats, deletes, pastes and the rest apply across the whole selected range, and
// undo and redo cover all of it.
export default class extends Controller {
  static targets = [ "grid", "entries", "input", "formula" ]

  connect() {
    this.cellWidth = cellSize(this.gridTarget).width
    this.originals = new Map() // each section's own cells, in DOM order, before any edits
    this.gridTarget.querySelectorAll(".sheet__section").forEach(section => {
      const cells = [ ...section.querySelectorAll(".cell") ]
      cells.forEach((cell, index) => {
        cell.dataset.sheetKey = `#${index}`
        if (cell.hidden) cell.dataset.sheetHidden = ""
      })
      this.originals.set(section.id, cells)
    })
    this.shells = new Map()
    this.styled = new WeakMap()
    this.histories = new Map()
    this.editable = true

    this.#listen()
    this.load()
  }

  disconnect() {
    this.listeners.forEach(([ target, type, listener ]) => target.removeEventListener(type, listener))
    this.note?.remove()
    this.chip?.remove()
  }

  // Opens the cells of the tab on screen.
  load() {
    this.#close()
    this.painter = null
    this.section = this.gridTarget.querySelector(".sheet__section:not([hidden])")
    this.cells = read(this.section.id)
    this.#render()
  }

  // The page's cells move at the phone breakpoint, uncovering some entries and covering others.
  relayout() {
    const { width } = cellSize(this.gridTarget)
    if (width === this.cellWidth) return

    this.cellWidth = width
    this.#render()
  }

  // Follows the selection: the active cell (box, and the cell drawn there) and the whole range.
  track({ detail: { box, cell, range } }) {
    this.box = box
    this.range = range ?? box
    this.cell = cell
    this.editable = !cell || cell.dataset.sheetKey !== undefined
    this.#showLink()
    this.#reflect()
  }

  // The phone FAQ is a sheet of its own, and a read-only one.
  untrack() {
    this.editable = false
  }

  // Toolbar and menu commands. Anything that isn't the editor's is someone else's.
  command({ detail: { command, value } }) {
    const run = this.#commands[command]
    if (!run || !this.editable || !this.box) return

    if (this.editing) this.#save()
    if (run.call(this, value) !== "editing") this.gridTarget.focus({ preventScroll: true })
  }

  // Keys pressed on the grid. Runs before cell-selection#move.
  key(event) {
    if (!this.editable || event.isComposing) return
    if (event.ctrlKey || event.metaKey) return this.#shortcut(event)
    if (event.altKey && event.shiftKey && event.code === "Digit5") return this.#run(event, "strikethrough")
    if (event.altKey) return

    if (event.key === "Escape" && this.painter) {
      this.painter = null
      this.#reflect()
    } else if (event.key === "Enter" || event.key === "F2") {
      this.#open(this.#raw(this.#activeKey), { typing: false })
    } else if (event.key === "Backspace" || event.key === "Delete") {
      this.#clearValues()
    } else if (event.key.length === 1) {
      this.#open(event.key, { typing: true }) // typing over a cell replaces it
    } else {
      return
    }
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  // A double-click on the grid, or a click on the formula bar.
  edit() {
    if (this.editable && !this.editing && this.box) this.#open(this.#raw(this.#activeKey), { typing: false })
  }

  // Keys pressed in the editor stay there, so space types a space rather than flapping.
  // Arrows move the caret, unless the cell was opened by typing over it: then, as in
  // Sheets, they save and move on.
  type(event) {
    event.stopPropagation()
    if (event.isComposing) return

    const arrow = event.key.startsWith("Arrow") && this.typing
    if (event.key === "Enter") this.#save(event.shiftKey ? "ArrowUp" : "ArrowDown")
    else if (event.key === "Tab") this.#save(event.shiftKey ? "ArrowLeft" : "ArrowRight")
    else if (arrow) this.#save(event.key)
    else if (event.key === "Escape") this.#cancel()
    else return
    event.preventDefault()
  }

  // Clicks in the editor place the caret; they aren't the grid's to select with.
  keep(event) {
    event.stopPropagation()
  }

  // The formula bar shows what's being typed.
  mirror() {
    this.formulaTarget.textContent = this.inputTarget.value
  }

  // Clicking away saves, as in Sheets.
  blur() {
    if (this.editing) this.#save()
  }

  // Commands

  get #commands() {
    return {
      undo: () => this.#undo(),
      redo: () => this.#redo(),
      copy: () => this.#copyCommand(false),
      cut: () => this.#copyCommand(true),
      paste: () => this.#pasteCommand(),
      delete: () => this.#clearValues(),

      bold: () => this.#toggle("bold"),
      italic: () => this.#toggle("italic"),
      underline: () => this.#toggle("underline"),
      strikethrough: () => this.#toggle("strikethrough"),
      textColor: value => this.#format({ textColor: value || undefined }),
      fillColor: value => this.#format({ fillColor: value || undefined }),
      fontFamily: value => this.#format({ fontFamily: value || undefined }),
      fontSize: value => this.#format({ fontSize: clamp(Number(value), 6, 400) || undefined }),
      fontSizeStep: value => this.#formatEach(key => ({ fontSize: clamp(this.#formatOf(key).fontSize + Number(value), 6, 400) })),
      numberFormat: value => this.#format({ numberFormat: value === "automatic" ? undefined : value, decimals: undefined }),
      decimals: value => this.#formatEach(key => ({ decimals: clamp(this.#decimalsOf(key) + Number(value), 0, 10) })),
      alignH: value => this.#format({ alignH: value }),
      alignV: value => this.#format({ alignV: value }),
      wrap: value => this.#format({ wrap: value }),
      rotate: value => this.#format({ rotate: value === 0 || value === "0" ? undefined : value }),
      borders: value => this.#borders(value),
      merge: value => this.#merge(value),
      clearFormat: () => this.#commit(cells => this.#keysIn(this.range).forEach(key => delete entry(cells, key).format)),
      paintFormat: () => this.#paintFormat(),

      insertFunction: value => this.#insertFunction(value),
      insertLink: value => this.#insertLink(value),
      comment: value => this.#commit(cells => { entry(cells, this.#activeKey).note = value?.trim() || undefined }),
      clearSheet: () => this.#commit(cells => Object.keys(cells).forEach(key => delete cells[key]))
    }
  }

  #run(event, command, value) {
    event.preventDefault()
    event.stopImmediatePropagation()
    this.#commands[command](value)
  }

  // Ctrl (or ⌘) shortcuts, as Sheets has them. Copy, cut and paste are left to the
  // browser, which fires the clipboard events handled below.
  #shortcut(event) {
    const letter = event.key.toLowerCase()
    if (letter === "c" || letter === "x" || letter === "v") return this.#expectClipboard(event)
    if (event.altKey) return

    if (event.shiftKey && NUMBER_SHORTCUTS[event.code]) return this.#run(event, "numberFormat", NUMBER_SHORTCUTS[event.code])
    if (event.shiftKey && ALIGN_SHORTCUTS[event.code]) return this.#run(event, "alignH", ALIGN_SHORTCUTS[event.code])
    if (event.shiftKey && event.code === "KeyX") return this.#run(event, "strikethrough")
    if (letter === "z") return this.#run(event, event.shiftKey ? "redo" : "undo")
    if (letter === "y") return this.#run(event, "redo")
    if (letter === "b" || letter === "i" || letter === "u") {
      return this.#run(event, { b: "bold", i: "italic", u: "underline" }[letter])
    }
    if (event.key === "\\") return this.#run(event, "clearFormat")
    if (event.key === ";") {
      event.preventDefault()
      return this.#writeAll([ [ this.#activeKey, formatValue(serialNow(), { numberFormat: "date" }) ] ])
    }
  }

  // Bold, italic and the rest follow the active cell: bold it if it isn't, unbold it if it is.
  #toggle(name) {
    this.#format({ [name]: !this.#formatOf(this.#activeKey)[name] })
  }

  #format(changes) {
    this.#formatEach(() => changes)
  }

  #formatEach(changesFor) {
    this.#commit(cells => this.#keysIn(this.range).forEach(key => {
      const changes = changesFor(key)
      const target = entry(cells, key)
      target.format = { ...target.format, ...changes }
    }))
  }

  // How many decimal places a cell shows now, so ".0" and ".00" count up and down from there.
  #decimalsOf(key) {
    return decimalsShown(this.values?.get(key), { ...this.implied?.get(key), ...this.cells[key]?.format })
  }

  #borders(kind) {
    const range = this.range
    this.#commit(cells => this.#keysIn(range).forEach(key => {
      const box = this.#boxOfKey(key)
      const edges = {
        top: box.row <= range.row,
        bottom: box.row + box.height >= range.row + range.height,
        left: box.column <= range.column,
        right: box.column + box.width >= range.column + range.width
      }
      const target = entry(cells, key)
      const borders = { ...target.format?.borders }

      if (kind === "none") return (target.format = { ...target.format, borders: undefined })
      if (kind === "all") Object.assign(borders, { top: true, bottom: true, left: true, right: true })
      if (kind === "outer") Object.entries(edges).forEach(([ side, edge ]) => edge && (borders[side] = true))
      if (kind === "inner") Object.entries(edges).forEach(([ side, edge ]) => edge || (borders[side] = true))
      if (edges[kind]) borders[kind] = true
      target.format = { ...target.format, borders: Object.keys(borders).length ? borders : undefined }
    }))
  }

  // Merging keeps the top-left cell, as Sheets does, and drops what the others held.
  #merge(kind) {
    const range = this.range
    this.#commit(cells => {
      const keys = this.#keysIn(range)
      keys.forEach(key => delete entry(cells, key).merge)
      if (kind === "unmerge") return

      const groups = []
      if (kind === "horizontal") {
        for (let row = range.row; row < range.row + range.height; row++) groups.push({ ...range, row, height: 1 })
      } else if (kind === "vertical") {
        for (let column = range.column; column < range.column + range.width; column++) groups.push({ ...range, column, width: 1 })
      } else {
        groups.push(range)
      }

      groups.filter(group => group.width * group.height > 1).forEach(group => {
        const [ anchor, ...rest ] = this.#keysIn(group)
        const box = this.#boxOfKey(anchor)
        entry(cells, anchor).merge = {
          width: Math.max(box.width, group.column + group.width - box.column),
          height: Math.max(box.height, group.row + group.height - box.row)
        }
        rest.forEach(key => {
          if (key.startsWith("#")) entry(cells, key).value = ""
          else delete entry(cells, key).value
        })
      })
    })
  }

  // The format painter: the active cell's format goes onto whatever's clicked next.
  #paintFormat() {
    this.painter = this.painter ? null : { format: this.cells[this.#activeKey]?.format }
    this.#reflect()
  }

  // Paints once the click has moved the selection, if the painter was waiting for that click.
  #paintLater() {
    const painter = this.painter
    if (painter) setTimeout(() => this.#paint(painter))
  }

  #paint(painter) {
    if (!painter || painter !== this.painter) return

    this.painter = null
    this.#commit(cells => this.#keysIn(this.range).forEach(key => {
      entry(cells, key).format = painter.format && structuredClone(painter.format)
    }))
    this.#reflect()
  }

  // Σ: over a range, the total goes in the cell under it; on one cell, the editor opens on "=SUM(".
  #insertFunction(name) {
    const range = this.range
    if (range.width * range.height === 1) {
      this.#open(`=${name}(`, { typing: false })
      return "editing"
    }

    const below = { column: range.column, row: range.row + range.height }
    const target = this.layout.covered.get(address(below)) ?? address(below)
    this.#writeAll([ [ target, `=${name}(${rangeAddress(range)})` ] ])
    this.element.dispatchEvent(new CustomEvent("menu-bar:command", { bubbles: true, detail: { command: "goTo", value: address(below) } }))
  }

  // A link keeps the cell's text as its label: =HYPERLINK("https://…", "label").
  #insertLink(url) {
    const key = this.#activeKey
    const link = linkOf(this.#raw(key))
    const label = link ? link.label : this.#displayed(key)
    if (!url) return this.#writeAll([ [ key, label ] ])

    const href = /^[a-z][\w+.-]*:|^\//i.test(url) ? url : `https://${url}`
    this.#writeAll([ [ key, `=HYPERLINK(${quote(href)}, ${quote(label || url)})` ] ])
  }

  // Values

  // Delete clears values but keeps formats, as in Sheets.
  #clearValues() {
    this.#writeAll(this.#keysIn(this.range).map(key => [ key, "" ]))
  }

  // Writes values into cells. A page cell given back its own value is itself again.
  #writeAll(writes) {
    this.#commit(cells => writes.forEach(([ key, value ]) => {
      const target = entry(cells, key)
      const original = this.#original(key)

      if (original && value === rawOf(original)) delete target.value
      else if (original) target.value = value
      else if (value === "") delete target.value
      else target.value = value
    }))
  }

  // Every change goes through here: it's saved, drawn, and undoable.
  #commit(change) {
    const before = JSON.stringify(this.cells)
    change(this.cells)
    prune(this.cells)
    if (JSON.stringify(this.cells) === before) return

    const history = this.#history
    history.undo.push(before)
    if (history.undo.length > HISTORY) history.undo.shift()
    history.redo = []
    this.#changed()
  }

  #undo() {
    this.#travel(this.#history.undo, this.#history.redo)
  }

  #redo() {
    this.#travel(this.#history.redo, this.#history.undo)
  }

  #travel(from, to) {
    const state = from.pop()
    if (state === undefined) return

    this.#close()
    to.push(JSON.stringify(this.cells))
    this.cells = JSON.parse(state)
    this.#changed()
  }

  #changed() {
    save(this.section.id, this.cells)
    this.#render()
    this.dispatch("change")
    this.#reflect()
  }

  get #history() {
    const id = this.section.id
    if (!this.histories.has(id)) this.histories.set(id, { undo: [], redo: [] })
    return this.histories.get(id)
  }

  // Clipboard. Copies are tab-separated text, which is what Sheets itself reads and
  // writes, so cells paste to and from real spreadsheets. Pasting what was copied here
  // brings its formulas (moved along) and formats; pasting what was cut moves it.

  #listen() {
    this.listeners = [
      [ document, "copy", event => this.#clipboard(event, "copy") ],
      [ document, "cut", event => this.#clipboard(event, "cut") ],
      [ document, "paste", event => this.#clipboard(event, "paste") ],
      [ this.gridTarget, "click", () => this.#paintLater() ],
      [ this.gridTarget, "mouseover", event => this.#hover(event) ],
      [ this.gridTarget, "mouseleave", () => this.#hover({}) ]
    ]
    this.listeners.forEach(([ target, type, listener ]) => target.addEventListener(type, listener))
  }

  #clipboard(event, type) {
    if (document.activeElement !== this.gridTarget || !this.editable || !this.box) return

    this.expected = null
    event.preventDefault()
    if (type === "paste") {
      this.#paste(event.clipboardData?.getData("text/plain") ?? "")
    } else {
      const { text, html } = this.#copy(type === "cut")
      event.clipboardData?.setData("text/plain", text)
      event.clipboardData?.setData("text/html", html)
    }
  }

  // Some browsers skip clipboard events when nothing on the page is selected; the
  // Clipboard API covers for them.
  #expectClipboard(event) {
    const type = { c: "copy", x: "cut", v: "paste" }[event.key.toLowerCase()]
    this.expected = type
    setTimeout(() => {
      if (this.expected !== type) return
      this.expected = null
      if (type === "paste") this.#pasteCommand()
      else this.#copyCommand(type === "cut")
    }, 100)
  }

  #copyCommand(cut) {
    const { text } = this.#copy(cut)
    navigator.clipboard?.writeText(text).catch(() => {})
  }

  async #pasteCommand() {
    let text = this.clip?.text ?? ""
    try {
      text = await navigator.clipboard.readText()
    } catch {}
    this.#paste(text)
  }

  #copy(cut) {
    const range = this.range
    const rows = []
    for (let row = range.row; row < range.row + range.height; row++) {
      const cells = []
      for (let column = range.column; column < range.column + range.width; column++) {
        const at = address({ column, row })
        const key = this.layout.covered.get(at) ?? at
        const anchor = this.layout.anchors.get(key) === at
        cells.push(anchor || !this.layout.covered.has(at) ? key : null)
      }
      rows.push(cells)
    }

    const grid = rows.map(cells => cells.map(key => {
      if (!key) return { text: "" }
      const original = this.#original(key)
      const data = this.cells[key] ?? {}
      const raw = data.value ?? (original ? original.textContent.trim().replace(/\s+/g, " ") : "")
      return { key, text: this.#displayed(key), raw, format: data.format, note: data.note }
    }))
    const text = grid.map(cells => cells.map(cell => tsvCell(cell.text)).join("\t")).join("\n")
    const html = `<table>${grid.map(cells => `<tr>${cells.map(cell => `<td>${escapeHTML(cell.text)}</td>`).join("")}</tr>`).join("")}</table>`

    this.clip = { text, grid, origin: { column: range.column, row: range.row }, cut, section: this.section.id }
    return { text, html }
  }

  #paste(text) {
    const clip = this.clip
    const ours = clip && clip.section === this.section.id && normalize(text) === normalize(clip.text)
    const grid = ours ? clip.grid : parseTSV(text).map(cells => cells.map(cell => ({ raw: cell })))
    if (!grid.length) return

    // One value pasted over a range fills the range, as in Sheets.
    const single = grid.length === 1 && grid[0].length === 1
    const range = this.range
    const [ height, width ] = single ? [ range.height, range.width ] : [ grid.length, Math.max(...grid.map(cells => cells.length)) ]

    this.#commit(cells => {
      if (ours && clip.cut) {
        clip.grid.flat().forEach(cell => cell.key && this.#clear(cells, cell.key))
        this.clip = null
      }
      for (let dy = 0; dy < height; dy++) {
        for (let dx = 0; dx < width; dx++) {
          const source = single ? grid[0][0] : grid[dy]?.[dx]
          if (!source) continue

          if (range.column + dx > 25) continue
          const at = address({ column: range.column + dx, row: range.row + dy })
          const key = this.layout.covered.get(at) ?? at
          if (this.layout.covered.has(at) && this.layout.anchors.get(key) !== at) continue

          const target = entry(cells, key)
          let raw = source.raw ?? ""
          if (ours && !clip.cut && raw.startsWith("=")) {
            raw = shift(raw, range.column - clip.origin.column + (single ? dx : 0), range.row - clip.origin.row + (single ? dy : 0))
          }
          const original = this.#original(key)
          if (original && raw === rawOf(original)) delete target.value
          else if (original || raw !== "") target.value = raw
          else delete target.value
          if (ours) {
            target.format = source.format && structuredClone(source.format)
            target.note = source.note
          }
        }
      }
    })
  }

  #clear(cells, key) {
    const target = entry(cells, key)
    delete target.format
    delete target.note
    delete target.merge
    if (this.#original(key)) target.value = ""
    else delete target.value
  }

  // The editor

  #open(value, { typing }) {
    const box = this.#boxOfKey(this.#activeKey)
    const input = this.inputTarget
    const format = this.#formatOf(this.#activeKey)

    this.editing = { key: this.#activeKey }
    this.typing = typing
    input.style.setProperty("--column", box.column + 1)
    input.style.setProperty("--row", box.row + 1)
    input.style.setProperty("--width", box.width)
    input.style.setProperty("--height", box.height)
    input.style.fontWeight = format.bold ? "700" : ""
    input.style.fontStyle = format.italic ? "italic" : ""
    input.style.fontFamily = this.cells[this.#activeKey]?.format?.fontFamily ? family(format.fontFamily) : ""
    input.style.color = format.textColor ?? ""
    input.value = value
    input.hidden = false
    input.focus({ preventScroll: true })
    input.setSelectionRange(value.length, value.length)
    this.mirror()
    this.#showLink()
  }

  // Saves the editor into its cell, then moves on if there's a key to move by.
  #save(key) {
    const { key: cell } = this.editing
    const value = this.inputTarget.value
    this.#close()
    this.#writeAll([ [ cell, value ] ])

    if (key) {
      this.gridTarget.focus({ preventScroll: true })
      this.dispatch("move", { detail: { key } })
    }
  }

  #cancel() {
    this.#close()
    this.gridTarget.focus({ preventScroll: true })
    this.dispatch("change") // puts the formula bar back
  }

  #close() {
    this.editing = null
    this.inputTarget.hidden = true
  }

  // Cells and keys

  // The active cell's key: the key of the cell drawn there, or the empty grid's address.
  get #activeKey() {
    return this.cell?.dataset.sheetKey ?? address(this.box)
  }

  // What a cell holds, as the editor and formula bar show it.
  #raw(key) {
    const value = this.cells[key]?.value
    if (value !== undefined) return value

    const original = this.#original(key)
    return original ? rawOf(original) : ""
  }

  #displayed(key) {
    const original = this.#original(key)
    if (original && this.cells[key]?.value === undefined) return original.textContent.trim().replace(/\s+/g, " ")
    return this.#text(key)
  }

  #text(key) {
    const value = this.values.get(key)
    if (value === undefined) return ""
    return formatValue(value, { ...this.implied.get(key), ...this.cells[key]?.format })
  }

  #original(key) {
    if (!key.startsWith("#")) return
    return this.originals.get(this.section.id)?.[Number(key.slice(1))]
  }

  // The keys of every cell a range touches, top-left first: page cells and merges by their
  // key, the empty grid by address.
  #keysIn({ column, row, width, height }) {
    const keys = new Set()
    for (let y = row; y < row + height; y++) {
      for (let x = column; x < column + width; x++) {
        const at = address({ column: x, row: y })
        keys.add(this.layout.covered.get(at) ?? at)
      }
    }
    return [ ...keys ]
  }

  #boxOfKey(key) {
    return this.layout.boxes.get(key) ?? { ...position(key.startsWith("#") ? "A1" : key), width: 1, height: 1 }
  }

  // The active cell's format, filled in from how it looks where nothing's been set, so
  // the toolbar reads true for the page's own cells too.
  #formatOf(key) {
    const stored = { ...this.implied?.get(key), ...this.cells[key]?.format }
    const element = this.#drawn(key)
    if (!element) return { fontSize: 14, fontFamily: "Arial", numberFormat: "automatic", ...stored }

    const style = getComputedStyle(element)
    const decoration = style.textDecorationLine
    return {
      bold: parseInt(style.fontWeight) >= 600,
      italic: style.fontStyle === "italic",
      underline: decoration.includes("underline"),
      strikethrough: decoration.includes("line-through"),
      fontSize: Math.round(parseFloat(style.fontSize)),
      fontFamily: style.fontFamily.split(",")[0].replaceAll(/["']/g, "").trim(),
      alignH: { "flex-end": "right", end: "right", right: "right", center: "center" }[style.justifyContent] ?? "left",
      alignV: { "flex-start": "top", start: "top", "flex-end": "bottom", end: "bottom" }[style.alignItems] ?? "middle",
      wrap: style.whiteSpace === "nowrap" ? "overflow" : "wrap",
      numberFormat: "automatic",
      ...stored
    }
  }

  #drawn(key) {
    if (!key.startsWith("#")) return this.entriesTarget.querySelector(`[data-sheet-key="${key}"]`)

    const original = this.#original(key)
    return original && (this.shells.get(original)?.isConnected ? this.shells.get(original) : original)
  }

  #reflect() {
    if (!this.box || !this.layout) return

    const history = this.#history
    this.dispatch("format", {
      detail: {
        format: this.#formatOf(this.#activeKey),
        canUndo: history.undo.length > 0,
        canRedo: history.redo.length > 0,
        painting: Boolean(this.painter)
      }
    })
  }

  // Drawing

  // Draws the tab: the page's cells (typed over, formatted, merged or as they are), then
  // the empty grid's, then works out every value.
  #render() {
    const size = cellSize(this.gridTarget)
    const originals = this.originals.get(this.section.id) ?? []
    const layout = { boxes: new Map(), anchors: new Map(), covered: new Map() }
    this.layout = layout

    // The page's own cells: a shell over each one typed over.
    const drawn = originals.map((original, index) => {
      const key = `#${index}`
      const data = this.cells[key]
      let shell = this.shells.get(original)
      this.#unstyle(original)

      if (data?.value !== undefined) {
        if (!shell) this.shells.set(original, shell = document.createElement("span"))
        if (shell.nextSibling !== original) original.before(shell)
        this.#unstyle(shell)
        shell.className = `${original.className} sheet-shell`
        shell.setAttribute("style", original.getAttribute("style") ?? "")
        shell.dataset.sheetKey = key
        shell.hidden = false
        const initial = original.dataset.cellSelectionTarget
        if (initial) shell.dataset.cellSelectionTarget = initial
        original.hidden = true
        return [ key, shell, original ]
      }

      shell?.remove()
      original.hidden = original.dataset.sheetHidden !== undefined
      return [ key, original, original ]
    })

    // Merged page cells grow to their merge; cells left inside a merge are hidden.
    drawn.forEach(([ key, element ]) => {
      const merge = this.cells[key]?.merge
      if (!merge || !element.offsetParent) return

      this.#style(element, {
        "justify-self": "start",
        "align-self": "start",
        "inline-size": `calc(${merge.width} * var(--cell-width) - 1px)`,
        "block-size": `calc(${merge.height} * var(--cell-height) - 1px)`,
        "max-inline-size": "none",
        "z-index": "3"
      })
    })
    const merges = []
    drawn.forEach(([ key, element ]) => {
      if (!element.offsetParent) return
      const box = boxOf(element, size)
      layout.boxes.set(key, box)
      if (this.cells[key]?.merge) merges.push([ key, box ])
    })
    Object.entries(this.cells).forEach(([ key, data ]) => {
      if (!key.startsWith("#") && data.merge) merges.push([ key, { ...position(key), ...data.merge } ])
    })

    const inside = (box, [ key, merge ]) => box.column >= merge.column && box.row >= merge.row &&
      box.column + box.width <= merge.column + merge.width && box.row + box.height <= merge.row + merge.height
    drawn.forEach(([ key, element ]) => {
      const box = layout.boxes.get(key)
      if (!box) return
      if (merges.some(merge => merge[0] !== key && inside(box, merge))) {
        element.hidden = true
        layout.boxes.delete(key)
      } else {
        this.#cover(key, box)
      }
    })

    // The empty grid's cells, unless the page (or a merge) already covers them.
    const entries = Object.entries(this.cells).filter(([ key ]) => !key.startsWith("#"))
    entries.forEach(([ key, data ]) => {
      const box = { ...position(key), width: data.merge?.width ?? 1, height: data.merge?.height ?? 1 }
      if (data.merge && !layout.covered.has(key)) this.#cover(key, box)
    })
    entries.forEach(([ key ]) => {
      if (!layout.covered.has(key)) this.#cover(key, { ...position(key), width: 1, height: 1 })
    })

    this.#calculate(drawn)

    const cells = entries.filter(([ key ]) => layout.anchors.get(key) === key).map(([ key, data ]) => {
      const box = layout.boxes.get(key)
      const cell = document.createElement("span")
      cell.dataset.sheetKey = key
      cell.dataset.formula = data.value ?? ""
      cell.style.gridArea = box.width * box.height > 1
        ? `${box.row + 1} / ${box.column + 1} / span ${box.height} / span ${box.width}`
        : `${box.row + 1} / ${box.column + 1}`
      this.#paintCell(cell, key, "cell sheet-entry")
      return cell
    })
    this.entriesTarget.replaceChildren(...cells, ...this.#noteMarkers())

    drawn.forEach(([ key, element, original ]) => {
      if (element !== original) {
        element.dataset.formula = this.cells[key].value
        this.#paintCell(element, key, element.className)
      } else {
        this.#decorate(element, key)
      }
    })
    this.#showLink()
  }

  // Notes get Sheets' black corner, drawn over the cell rather than in it, so it never
  // fights with a page cell's own decorations.
  #noteMarkers() {
    return [ ...this.layout.boxes ].filter(([ key ]) => this.cells[key]?.note).map(([ , box ]) => {
      const marker = document.createElement("span")
      marker.className = "sheet-note-marker"
      marker.style.gridArea = `${box.row + 1} / ${box.column + 1} / span ${box.height} / span ${box.width}`
      return marker
    })
  }

  // Where cells overlap, the topmost (the last one) wins, as it does for the selection.
  #cover(key, box) {
    const { boxes, anchors, covered } = this.layout
    boxes.set(key, box)
    anchors.set(key, address(box))
    for (let row = box.row; row < box.row + box.height; row++) {
      for (let column = box.column; column < box.column + box.width; column++) {
        covered.set(address({ column, row }), key)
      }
    }
  }

  // An entry or shell: its value, formatted, and its kind for the default alignment.
  #paintCell(cell, key, className) {
    const value = this.values.get(key) ?? ""
    const format = this.cells[key]?.format ?? {}
    const link = linkOf(this.cells[key]?.value ?? "")
    const base = className.replace(/\s*sheet-entry--\w+/g, "")
    cell.className = `${base} sheet-entry--${kind(value)}${link ? " sheet-entry--link" : ""}`

    const text = this.#text(key)
    if (format.rotate !== undefined && format.rotate !== 0) {
      const inner = document.createElement("span")
      inner.className = "sheet-text"
      inner.textContent = text
      if (format.rotate === "vertical") inner.classList.add("sheet-text--vertical")
      else inner.style.rotate = `${-Number(format.rotate)}deg`
      cell.replaceChildren(inner)
    } else {
      cell.textContent = text
    }
    this.#decorate(cell, key)
  }

  // Formats, borders and notes, as inline styles (which win over the layered CSS).
  #decorate(element, key) {
    const data = this.cells[key]
    const format = data?.format ?? {}
    const styles = {}

    if (format.bold !== undefined) styles["font-weight"] = format.bold ? "700" : "400"
    if (format.italic !== undefined) styles["font-style"] = format.italic ? "italic" : "normal"
    if (format.underline !== undefined || format.strikethrough !== undefined) {
      const lines = [ format.underline && "underline", format.strikethrough && "line-through" ].filter(Boolean)
      styles["text-decoration-line"] = lines.join(" ") || "none"
    }
    if (format.textColor) styles.color = format.textColor
    if (format.fillColor) styles.background = format.fillColor
    if (format.fontFamily) styles["font-family"] = family(format.fontFamily)
    if (format.fontSize) styles["font-size"] = `${format.fontSize}px`
    if (format.alignH) {
      styles["justify-content"] = { left: "flex-start", center: "center", right: "flex-end" }[format.alignH]
      styles["text-align"] = format.alignH
    }
    if (format.alignV) styles["align-items"] = { top: "flex-start", middle: "center", bottom: "flex-end" }[format.alignV]
    if (format.wrap === "wrap") Object.assign(styles, { "white-space": "normal", "overflow-wrap": "anywhere", "line-height": "1.25" })
    if (format.wrap === "overflow") Object.assign(styles, { "white-space": "nowrap", overflow: "visible", "text-overflow": "clip", "z-index": "1" })
    if (format.wrap === "clip") Object.assign(styles, { "white-space": "nowrap", overflow: "hidden", "text-overflow": "clip" })
    if (format.rotate !== undefined && element.dataset.sheetKey?.startsWith("#") && !element.classList.contains("sheet-shell")) {
      styles.rotate = format.rotate === "vertical" ? "90deg" : `${-Number(format.rotate)}deg`
    }

    const borders = Object.entries({ top: "0 -1px", bottom: "0 1px", left: "-1px 0", right: "1px 0" })
      .filter(([ side ]) => format.borders?.[side])
      .map(([ , offset ]) => `${offset} 0 0 ${BORDER}`)
    if (borders.length) styles["box-shadow"] = borders.join(", ")

    this.#style(element, styles)
    element.classList.toggle("sheet-noted", Boolean(data?.note))
    if (data?.note) element.dataset.note = data.note
    else delete element.dataset.note
  }

  // Sets inline styles, remembering them so they can come off again (other controllers
  // may set styles of their own on the page's cells).
  #style(element, styles) {
    const set = this.styled.get(element) ?? new Set()
    Object.entries(styles).forEach(([ property, value ]) => {
      element.style.setProperty(property, value)
      set.add(property)
    })
    this.styled.set(element, set)
  }

  #unstyle(element) {
    this.styled.get(element)?.forEach(property => element.style.removeProperty(property))
    this.styled.delete(element)
  }

  // Works out every value. Formulas read other cells, working them out first, and the
  // page's own cells as they read; a formula that ends up reading itself is a #REF!.
  #calculate(drawn) {
    const values = new Map()
    const implied = new Map()
    const pending = new Set()
    const { anchors, covered } = this.layout
    const byAddress = new Map()
    const page = new Map()

    drawn.forEach(([ key, element, original ]) => {
      if (!anchors.has(key)) return
      if (this.cells[key]?.value !== undefined) byAddress.set(anchors.get(key), key)
      else page.set(anchors.get(key), literal(original.textContent.trim().replace(/\s+/g, " ")))
    })
    Object.entries(this.cells).forEach(([ key, data ]) => {
      if (!key.startsWith("#") && anchors.get(key) === key && data.value !== undefined) byAddress.set(key, key)
    })

    const valueOf = key => {
      if (values.has(key)) return values.get(key)
      if (pending.has(key)) return new SheetError("#REF!")

      const raw = this.cells[key].value
      const numberFormat = this.cells[key].format?.numberFormat
      pending.add(key)
      let value
      if (raw.startsWith("=") && numberFormat !== "plain") {
        value = evaluate(raw.slice(1), (column, row) => valueAt(address({ column, row })))
        const hint = impliedByFormula(raw)
        if (hint) implied.set(key, hint)
      } else {
        const typed = interpret(raw, numberFormat)
        value = typed.value
        if (typed.implied) implied.set(key, typed.implied)
      }
      pending.delete(key)
      values.set(key, value)
      return value
    }
    const valueAt = at => {
      const key = byAddress.get(at)
      if (key) return valueOf(key)
      if (page.has(at)) return page.get(at)
      return ""
    }

    this.values = values
    this.implied = implied
    byAddress.forEach(valueOf)
  }

  // Notes show on hover, like Sheets' black-cornered cells.
  #hover({ target }) {
    const cell = target?.closest?.("[data-note]")
    if (!cell || !this.gridTarget.contains(cell)) {
      if (this.note) this.note.hidden = true
      return
    }

    this.note ??= this.#popup("sheet-note")
    this.note.textContent = cell.dataset.note
    this.#place(this.note, cell)
  }

  // A selected link gets the little chip Sheets shows, to follow it.
  #showLink() {
    const link = !this.editing && this.box && this.layout && linkOf(this.cells[this.#activeKey]?.value ?? "")
    const cell = link && this.#drawn(this.#activeKey)
    if (!cell) {
      if (this.chip) this.chip.hidden = true
      return
    }

    this.chip ??= this.#popup("sheet-link-chip")
    const anchor = document.createElement("a")
    anchor.href = link.url
    anchor.target = "_blank"
    anchor.rel = "noopener"
    anchor.textContent = link.url
    this.chip.replaceChildren(anchor)
    this.#place(this.chip, cell, { below: true })
  }

  #popup(className) {
    const popup = document.createElement("div")
    popup.className = className
    popup.hidden = true
    const stop = event => event.stopPropagation()
    popup.addEventListener("click", stop)
    popup.addEventListener("mousedown", stop)
    popup.addEventListener("pointerdown", stop)
    this.gridTarget.append(popup)
    return popup
  }

  #place(popup, cell, { below = false } = {}) {
    const grid = this.gridTarget.getBoundingClientRect()
    const box = cell.getBoundingClientRect()
    popup.hidden = false
    const zoom = zoomOf(this.gridTarget) // rects are in screen pixels, the popup sits in the zoomed grid
    popup.style.left = `${((below ? box.left : box.right) - grid.left) / zoom + 4}px`
    popup.style.top = `${((below ? box.bottom : box.top) - grid.top) / zoom + (below ? 4 : 0)}px`
  }
}

// A cell's entry in the tab's cells, made on first use (and pruned when it ends up empty).
function entry(cells, key) {
  return (cells[key] ??= {})
}

function prune(cells) {
  Object.entries(cells).forEach(([ key, data ]) => {
    if (data.format) {
      Object.keys(data.format).forEach(name => data.format[name] === undefined && delete data.format[name])
      if (!Object.keys(data.format).length) delete data.format
    }
    Object.keys(data).forEach(name => data[name] === undefined && delete data[name])
    if (!Object.keys(data).length) delete cells[key]
  })
}

// A page cell's own raw value: its formula if it shows one, else its text.
function rawOf(cell) {
  return cell.dataset.formula ?? cell.textContent.trim().replace(/\s+/g, " ")
}

// The URL and label of =HYPERLINK("url", "label").
function linkOf(raw) {
  const match = raw.match(/^=\s*HYPERLINK\(\s*"((?:[^"]|"")*)"\s*(?:,\s*"((?:[^"]|"")*)"\s*)?\)\s*$/i)
  if (!match) return
  const url = match[1].replaceAll('""', '"')
  return { url, label: match[2]?.replaceAll('""', '"') ?? url }
}

function quote(text) {
  return `"${text.replaceAll('"', '""')}"`
}

function family(name) {
  return `"${name}", var(--font-cell)`
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

function rangeAddress(range) {
  const end = { column: range.column + range.width - 1, row: range.row + range.height - 1 }
  return `${address(range)}:${address(end)}`
}

function serialNow() {
  const now = new Date()
  return (Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) - Date.UTC(1899, 11, 30)) / 86400000
}

// Tab-separated values, quoted as Sheets quotes them.
function tsvCell(text) {
  return /[\t\n"]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
}

function parseTSV(text) {
  const rows = [ [] ]
  let cell = ""
  let quoted = false
  text = normalize(text).replace(/\n$/, "")

  for (let index = 0; index < text.length; index++) {
    const char = text[index]
    if (quoted) {
      if (char === '"' && text[index + 1] === '"') cell += text[index++]
      else if (char === '"') quoted = false
      else cell += char
    } else if (char === '"' && cell === "") {
      quoted = true
    } else if (char === "\t") {
      rows.at(-1).push(cell)
      cell = ""
    } else if (char === "\n") {
      rows.at(-1).push(cell)
      rows.push([])
      cell = ""
    } else {
      cell += char
    }
  }
  rows.at(-1).push(cell)
  return text === "" ? [] : rows
}

function normalize(text) {
  return text.replaceAll("\r\n", "\n").replaceAll("\r", "\n")
}

function escapeHTML(text) {
  return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
}

// Storage can be missing or full (private windows, blocked site data); the sheet still works.
// Tabs saved before formatting kept plain values under another key; they move over.
function read(id) {
  try {
    const sheet = JSON.parse(localStorage.getItem(STORAGE_KEY + id))
    if (sheet?.cells) return sheet.cells

    const entries = JSON.parse(localStorage.getItem(OLD_STORAGE_KEY + id))
    if (!entries) return {}
    const cells = Object.fromEntries(Object.entries(entries).map(([ key, value ]) => [ key, { value: String(value) } ]))
    save(id, cells)
    localStorage.removeItem(OLD_STORAGE_KEY + id)
    return cells
  } catch {
    return {}
  }
}

function save(id, cells) {
  try {
    if (Object.keys(cells).length) {
      localStorage.setItem(STORAGE_KEY + id, JSON.stringify({ cells }))
    } else {
      localStorage.removeItem(STORAGE_KEY + id)
    }
  } catch {}
}
