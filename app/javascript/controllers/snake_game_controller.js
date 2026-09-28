import { Controller } from "@hotwired/stimulus"

const COLUMNS = 5
const ROWS = 8
const TICK = 230
const DIRECTIONS = { ArrowUp: [ 0, -1 ], ArrowDown: [ 0, 1 ], ArrowLeft: [ -1, 0 ], ArrowRight: [ 1, 0 ] }
const FORMULAS = { head: "=HEAD(snake)", body: "=AND(snake, TRUE)", food: "=APPLE()" }

// Snake, played on a 5 × 8 block of cells in the hero. While a game runs the
// arrow keys steer; the rest of the time they belong to the cell selection.
export default class extends Controller {
  static targets = [ "cell", "play", "score" ]

  connect() {
    this.#reset()
    this.#draw()
  }

  disconnect() {
    clearInterval(this.timer)
  }

  start() {
    if (this.playing) return

    this.#reset()
    this.playing = true
    this.timer = setInterval(() => this.#tick(), TICK)
    this.#draw()
  }

  pause() {
    if (!this.playing) return

    clearInterval(this.timer)
    this.playing = false
    this.#draw()
  }

  // Runs before the cell selection sees the key, and keeps it from moving.
  steer(event) {
    const direction = DIRECTIONS[event.key]
    if (!this.playing || !direction) return

    event.preventDefault()
    event.stopImmediatePropagation()

    const [ x, y ] = this.direction
    const reversing = direction[0] === -x && direction[1] === -y
    if (!reversing) this.nextDirection = direction
  }

  #reset() {
    this.body = [ [ 2, 4 ], [ 1, 4 ], [ 0, 4 ] ]
    this.direction = this.nextDirection = [ 1, 0 ]
    this.food = [ 3, 1 ]
    this.score = 0
    this.over = false
  }

  #tick() {
    const [ dx, dy ] = this.direction = this.nextDirection
    const [ x, y ] = this.body[0]
    const head = [ x + dx, y + dy ]

    if (!this.#onBoard(head) || this.#onSnake(head)) return this.#gameOver()

    this.body.unshift(head)
    if (same(head, this.food)) {
      this.score++
      this.food = this.#randomFood()
      if (!this.food) return this.#gameOver() // the snake fills the board
    } else {
      this.body.pop()
    }
    this.#draw()
  }

  #gameOver() {
    clearInterval(this.timer)
    this.playing = false
    this.over = true
    this.#draw()
  }

  #draw() {
    const pieces = new Map(this.body.map((part, index) => [ indexOf(part), index === 0 ? "head" : "body" ]))
    if (this.food) pieces.set(indexOf(this.food), "food")

    this.cellTargets.forEach((cell, index) => {
      const piece = pieces.get(index)
      for (const name of Object.keys(FORMULAS)) {
        cell.classList.toggle(`snake-board__cell--${name}`, piece === name)
      }
      if (piece) {
        cell.dataset.formula = FORMULAS[piece]
      } else {
        delete cell.dataset.formula
      }
    })

    this.playTarget.textContent = this.playing ? "Playing · arrow keys steer" : this.over ? "▶ Game over. Play again" : "▶ Play snake"
    this.scoreTarget.textContent = `SCORE ${this.score}`
    this.scoreTarget.dataset.formula = `=COUNTA(apples_eaten) → ${this.score}`
    this.dispatch("draw")
  }

  #onBoard([ x, y ]) {
    return x >= 0 && x < COLUMNS && y >= 0 && y < ROWS
  }

  #onSnake(point) {
    return this.body.some(part => same(part, point))
  }

  #randomFood() {
    const free = Array.from({ length: COLUMNS * ROWS }, (_, index) => [ index % COLUMNS, Math.floor(index / COLUMNS) ])
      .filter(point => !this.#onSnake(point))
    return free[Math.floor(Math.random() * free.length)]
  }
}

function indexOf([ x, y ]) {
  return y * COLUMNS + x
}

function same(a, b) {
  return a[0] === b[0] && a[1] === b[1]
}
