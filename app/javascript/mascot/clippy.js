import { ANIMATIONS, COLUMNS } from "mascot/clippy_animations"

// Clippy, on his sprite sheet (mascot/clippy.webp), playing clippy.js's animations: the sprite element shows one
// 124×93 frame at a time through its --frame-x and --frame-y custom properties.
//
// He has moods, each a set of animations he moves between with pauses in his rest pose: `feel("typing")` keeps him
// at it until he's told to feel something else. `play(name)` runs one animation through, and `congratulate()` is
// his tick with his own sounds.

const REST = ANIMATIONS.RestPose[0].frame
// Long-running animations (thinking, typing) loop through their branches; past this they take their way out.
const LOOP_FOR = 6000

// What he gets up to in each mood, and how long he rests (ms, a range) between bits.
const MOODS = {
  // Waiting on you, idly.
  idle: { animations: [ "IdleFingerTap", "IdleHeadScratch", "IdleEyeBrowRaise", "LookDown", "LookUp", "LookRight" ], rest: [ 4000, 9000 ] },
  // Something needs doing: he waves for your attention now and then.
  attention: { animations: [ "GetAttention", "Alert", "IdleFingerTap" ], rest: [ 3000, 6000 ] },
  // Working something out with you.
  thinking: { animations: [ "Thinking", "IdleHeadScratch", "LookUp" ], rest: [ 1500, 4000 ] },
  // Pointing at what's next.
  explaining: { animations: [ "Explain", "LookDown", "IdleEyeBrowRaise" ], rest: [ 3000, 7000 ] },
  // Heads down, building alongside you.
  typing: { animations: [ "Writing" ], rest: [ 300, 1200 ] },
  // On a break: mostly still, the odd glance around.
  resting: { animations: [ "LookUp", "LookRight", "IdleEyeBrowRaise" ], rest: [ 7000, 14000 ] },
  // Pleased with you.
  happy: { animations: [ "Wave", "IdleEyeBrowRaise", "LookRight" ], rest: [ 5000, 10000 ] }
}

export class Clippy {
  // `sounds` maps the names in his animations ("first", "second") to their URLs.
  constructor(sprite, sounds = {}) {
    this.sprite = sprite
    this.sounds = Object.fromEntries(Object.entries(sounds).map(([ name, url ]) => {
      const audio = new Audio(url)
      audio.preload = "auto"
      return [ name, audio ]
    }))
    this.#show(REST)
  }

  // Keeps him in a mood until another one (or `stop()`), starting with `first` if given.
  feel(mood, { first } = {}) {
    if (!MOODS[mood]) return
    this.stop()
    this.mood = mood
    if (first) this.play(first, { then: () => this.#carryOn() })
    else this.#carryOn(true)
  }

  // His tick, with sounds, then `done` (or back to his mood).
  congratulate(done) {
    this.play("Congratulate", { then: done })
  }

  // One animation through, then `then` (or back to whatever mood he was in).
  play(name, { then } = {}) {
    clearTimeout(this.timer)
    const frames = ANIMATIONS[name]
    if (!frames) return
    const finish = () => (then ? then() : this.#carryOn())
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return this.#hold(frames, finish)
    this.#step(frames, 0, Date.now() + LOOP_FOR, finish)
  }

  stop() {
    clearTimeout(this.timer)
    this.mood = null
    this.#show(REST)
  }

  // A rest in his pose, then the next bit of his mood.
  #carryOn(soon = false) {
    if (!this.mood) return this.#show(REST)
    const { animations, rest: [ shortest, longest ] } = MOODS[this.mood]
    this.#show(REST)
    const wait = soon ? 300 : shortest + Math.random() * (longest - shortest)
    this.timer = setTimeout(() => {
      const mood = this.mood
      this.play(animations[Math.floor(Math.random() * animations.length)], { then: () => this.mood === mood && this.#carryOn() })
    }, wait)
  }

  // Follows the animation's branches (how it loops) until it's run long enough, then its way out.
  #step(frames, index, until, finish) {
    if (index >= frames.length) return finish()
    const frame = frames[index]
    if (frame.frame !== undefined) this.#show(frame.frame)
    if (frame.sound) this.#sound(frame.sound)
    this.timer = setTimeout(() => this.#step(frames, this.#next(frame, index, until), until, finish), frame.duration)
  }

  #next(frame, index, until) {
    if (Date.now() > until) return frame.exitBranch ?? index + 1
    let roll = Math.random() * 100
    for (const [ target, weight ] of frame.branches ?? []) {
      if (roll < weight) return target
      roll -= weight
    }
    return index + 1
  }

  // With reduced motion: the animation's most telling frame (its longest), held a moment.
  #hold(frames, finish) {
    const still = frames.reduce((longest, frame) => (frame.frame !== undefined && frame.duration > (longest?.duration ?? -1) ? frame : longest), null)
    if (still) this.#show(still.frame)
    frames.filter((frame) => frame.sound).slice(-1).forEach((frame) => this.#sound(frame.sound))
    this.timer = setTimeout(finish, 1300)
  }

  #show(frame) {
    this.sprite.style.setProperty("--frame-x", frame % COLUMNS)
    this.sprite.style.setProperty("--frame-y", Math.floor(frame / COLUMNS))
  }

  // From the start each time; a browser that won't play it just stays quiet.
  #sound(name) {
    const audio = this.sounds[name]
    if (!audio) return
    audio.currentTime = 0
    audio.play().catch(() => {})
  }
}
