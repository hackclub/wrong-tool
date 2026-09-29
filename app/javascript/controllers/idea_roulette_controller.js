import { Controller } from "@hotwired/stimulus"

const TICK = 80
const GENRE_SETTLES = 1000
const PLATFORM_SETTLES = 1700

// Idea roulette: spins a genre and a platform like two slot reels, the genre settling
// first. Lands instantly for reduced motion. Keeps the last few spins in a log.
export default class extends Controller {
  static targets = [ "genre", "platform", "button", "result", "logHeading", "logNumber", "logEntry" ]
  static values = { genres: Array, platforms: Array }

  connect() {
    this.log = []
  }

  disconnect() {
    clearInterval(this.timer)
  }

  spin() {
    if (this.spinning) return

    const genre = this.#pick(this.genresValue)
    const platform = this.#pick(this.platformsValue)
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return this.#land(genre, platform)

    const started = Date.now()
    this.spinning = true
    this.buttonTarget.textContent = "spinning…"
    this.resultTarget.textContent = "…"
    this.timer = setInterval(() => {
      const elapsed = Date.now() - started
      if (elapsed > PLATFORM_SETTLES) return this.#land(genre, platform)

      const genreRolling = elapsed < GENRE_SETTLES
      this.#show(this.genreTarget, genreRolling ? this.#pick(this.genresValue) : genre, genreRolling)
      this.#show(this.platformTarget, this.#pick(this.platformsValue), true)
    }, TICK)
  }

  #land(genre, platform) {
    clearInterval(this.timer)
    this.spinning = false
    this.#show(this.genreTarget, genre, false)
    this.#show(this.platformTarget, platform, false)

    const idea = `make a ${genre} in ${platform}`
    this.buttonTarget.textContent = "Spin ↻"
    this.resultTarget.textContent = `${idea}.`
    this.log = [ idea, ...this.log ].slice(0, this.logEntryTargets.length)
    this.#drawLog()
    this.dispatch("change")
  }

  #show(reel, text, rolling) {
    reel.textContent = text
    reel.dataset.formula = `="${text}"`
    reel.classList.toggle("ideas__reel--rolling", rolling)
  }

  // Newest first, numbered so the newest has the highest number.
  #drawLog() {
    this.logHeadingTarget.hidden = false
    this.logEntryTargets.forEach((entry, index) => {
      const idea = this.log[index]
      const number = this.logNumberTargets[index]
      entry.hidden = number.hidden = !idea
      entry.textContent = idea ?? ""
      number.textContent = idea ? this.log.length - index : ""
    })
  }

  #pick(list) {
    return list[Math.floor(Math.random() * list.length)]
  }
}
