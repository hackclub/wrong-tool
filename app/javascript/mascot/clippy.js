// Clippy, drawn from a strip of his "Congratulate" animation (from clippy.js's Clippy agent) with his own
// sounds. The sprite element shows one 124×93 frame at a time through its --frame custom property.

// [frame in the strip, how long it shows (ms), sound to start]. He bends into a tick, holds it, waves it and
// straightens back up.
const CONGRATULATE = [
  [ 0, 100, "first" ], [ 1, 10 ], [ 2, 10 ], [ 3, 10, "second" ], [ 4, 10 ], [ 5, 10 ], [ 6, 10 ], [ 7, 10 ], [ 8, 10 ], [ 9, 100 ],
  [ 10, 100 ], [ 11, 100 ], [ 12, 600 ], [ 13, 100 ], [ 14, 100 ], [ 12, 600 ],
  [ 15, 100 ], [ 16, 100 ], [ 17, 100 ], [ 18, 100 ], [ 19, 100 ], [ 0, 100 ]
]
// With reduced motion he just holds the tick for this long.
const HOLD_TICK = 1300

export class Clippy {
  // `sounds` maps the names in CONGRATULATE to their URLs.
  constructor(sprite, sounds = {}) {
    this.sprite = sprite
    this.sounds = Object.fromEntries(Object.entries(sounds).map(([ name, url ]) => {
      const audio = new Audio(url)
      audio.preload = "auto"
      return [ name, audio ]
    }))
  }

  // Plays his congratulations once through (starting over if he's mid-way), then `done`.
  congratulate(done) {
    this.stop()
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#show(12)
      this.#play("second")
      this.timer = setTimeout(() => this.#rest(done), HOLD_TICK)
    } else {
      this.#step(0, done)
    }
  }

  stop() {
    clearTimeout(this.timer)
  }

  #step(index, done) {
    if (index === CONGRATULATE.length) return this.#rest(done)
    const [ frame, duration, sound ] = CONGRATULATE[index]
    this.#show(frame)
    if (sound) this.#play(sound)
    this.timer = setTimeout(() => this.#step(index + 1, done), duration)
  }

  #rest(done) {
    this.#show(0)
    done?.()
  }

  #show(frame) {
    this.sprite.style.setProperty("--frame", frame)
  }

  // From the start each time; a browser that won't play it just stays quiet.
  #play(name) {
    const audio = this.sounds[name]
    if (!audio) return
    audio.currentTime = 0
    audio.play().catch(() => {})
  }
}
