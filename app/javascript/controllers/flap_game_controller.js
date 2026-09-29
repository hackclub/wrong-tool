import { Controller } from "@hotwired/stimulus"

// A copy of flap in the sheets, the Google Sheets game: a 36 × 44 board with 40 rows
// of sky over the ground. FLAP (or space, or a click on the board) starts and flaps.
const COLUMNS = 36
const SKY = 40
const TICK = 80
const GRAVITY = 0.35
const FLAP = -1.9
const MAX_FALL = 2.6

const BIRD_X = 5
const GAP = 15
const PIPE_SPACING = 14
const CLOUDS = [ [ 3, 3 ], [ 3, 4 ], [ 3, 5 ], [ 3, 6 ], [ 6, 26 ], [ 6, 27 ] ] // [row, column]
const GROUND = [ "grass", "sand", "sand", "soil" ]

// The bird as [row, column, kind] offsets from its top-left corner.
const BIRD = [
  [ 0, 1, "bird" ], [ 0, 2, "bird" ], [ 0, 3, "bird" ], [ 0, 4, "eye" ],
  [ 1, 0, "bird" ], [ 1, 1, "bird" ], [ 1, 2, "bird" ], [ 1, 3, "bird" ], [ 1, 4, "bird" ], [ 1, 5, "beak" ], [ 1, 6, "beak" ],
  [ 2, 0, "wing" ], [ 2, 1, "bird" ], [ 2, 2, "bird" ], [ 2, 3, "bird" ], [ 2, 4, "bird" ]
]

export default class extends Controller {
  static targets = [ "board", "score" ]

  connect() {
    this.pixels = [ ...this.boardTarget.children ]
    this.drawn = []
    this.best = 0
    this.#reset()
    this.#draw()
  }

  disconnect() {
    clearInterval(this.timer)
  }

  // Flapping also starts a game that isn't running (or restarts one that crashed).
  flap() {
    if (!this.running) return this.#run(true)

    this.velocity = FLAP
  }

  pause() {
    this.#run(false)
  }

  // Space flaps (and starts); ↑ flaps while the game runs. Either way the cell selection
  // doesn't move. Runs before cell-selection#move.
  key(event) {
    const flapKey = event.key === " " || (event.key === "ArrowUp" && this.running)
    if (!flapKey || !this.boardTarget.offsetParent) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.flap()
  }

  #run(running) {
    clearInterval(this.timer)
    if (running && this.over) this.#reset()

    this.running = running
    this.boardTarget.classList.toggle("flap__board--running", running)
    if (running) {
      this.velocity = FLAP
      this.timer = setInterval(() => this.#tick(), TICK)
    }
    this.#draw()
    this.dispatch("change")
  }

  #reset() {
    this.y = 19
    this.velocity = 0
    this.pipes = [ { x: 28, gapTop: 16 } ]
    this.score = 0
    this.over = false
  }

  #tick() {
    this.velocity = Math.min(MAX_FALL, this.velocity + GRAVITY)
    this.y = Math.max(0, this.y + this.velocity) // the sky is a ceiling, not a wall
    if (this.y === 0) this.velocity = Math.max(0, this.velocity)

    this.pipes = this.pipes.map(pipe => ({ ...pipe, x: pipe.x - 1 })).filter(pipe => pipe.x > -2)
    const passed = this.pipes.filter(pipe => pipe.x + 3 === BIRD_X).length
    this.score += passed
    if (passed) this.dispatch("change")
    const last = this.pipes.at(-1)
    if (last.x <= COLUMNS - PIPE_SPACING) {
      this.pipes.push({ x: last.x + PIPE_SPACING, gapTop: 3 + Math.floor(Math.random() * (SKY - GAP - 6)) })
    }

    if (this.#crashed()) {
      this.over = true
      this.best = Math.max(this.best, this.score)
      this.#run(false)
    } else {
      this.#draw()
    }
  }

  #crashed() {
    const top = Math.round(this.y)
    return BIRD.some(([ row, column ]) => {
      const y = top + row
      return y >= SKY || this.#pipeAt(y, BIRD_X + column)
    })
  }

  // "stem" or "cap" (with "cap-edge" on the lip) where a pipe covers the pixel.
  #pipeAt(row, column) {
    for (const { x, gapTop } of this.pipes) {
      const gapBottom = gapTop + GAP
      if (row >= gapTop && row < gapBottom) continue

      const onCap = row >= gapTop - 2 && row < gapBottom + 2
      if (onCap && (column === x - 1 || column === x + 3)) return "cap-edge"
      if (column >= x && column <= x + 2) return onCap ? "cap" : "stem"
    }
  }

  #draw() {
    const kinds = new Array(this.pixels.length).fill("")
    const at = (row, column) => row * COLUMNS + column

    CLOUDS.forEach(([ row, column ]) => kinds[at(row, column)] = "cloud")
    GROUND.forEach((kind, index) => kinds.fill(kind, at(SKY + index, 0), at(SKY + index + 1, 0)))
    for (let row = 0; row < SKY; row++) {
      for (let column = 0; column < COLUMNS; column++) {
        const pipe = this.#pipeAt(row, column)
        if (pipe) kinds[at(row, column)] = pipe
      }
    }
    const top = Math.max(0, Math.min(SKY - 3, Math.round(this.y)))
    BIRD.forEach(([ row, column, kind ]) => kinds[at(top + row, BIRD_X + column)] = kind)

    kinds.forEach((kind, index) => {
      if (this.drawn[index] === kind) return
      this.pixels[index].className = kind ? `flap__pixel flap__pixel--${kind}` : "flap__pixel"
      this.drawn[index] = kind
    })

    this.scoreTarget.textContent = `score ${this.score} · best ${Math.max(this.best, this.score)}`
  }
}
