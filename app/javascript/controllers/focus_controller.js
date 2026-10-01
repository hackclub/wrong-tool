import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"
import { Radio, TRACKS } from "focus/radio"

const BREAK_SECONDS = 5 * 60
const KEYS = 22

// "Start session": a focus timer over the whole page, one round of your daily pace, with Wrong Tool Radio playing
// and Clippy bobbing along at the keyboard. Hackatime logs the time on its own; this is only for focus. When a
// round's done he congratulates you, and you can go again, take a five-minute break or head back.
export default class extends Controller {
  static targets = [ "overlay", "label", "title", "clock", "bar", "note", "toggle", "toggleLabel", "end", "live", "done",
                     "tracked", "clippy", "sprite", "keys", "noteLeft", "noteRight", "trackTag", "trackName", "trackNumber",
                     "equalizer", "music" ]
  static values = { minutes: Number, title: String, hoursLogged: Number, hoursGoal: Number, sounds: Object }

  connect() {
    this.clippy = new Clippy(this.spriteTarget, this.soundsValue)
    this.track = 0
    this.keysTarget.innerHTML = "<span></span>".repeat(KEYS)
    this.equalizerTarget.innerHTML = "<span></span>".repeat(20)
  }

  disconnect() {
    this.#stop()
    this.clippy.stop()
  }

  start() {
    this.#stop()
    this.overlayTarget.hidden = false
    this.beat = 0
    try {
      this.radio = new Radio(() => this.#onBeat())
      this.radio.setTrack(this.track)
    } catch {
      this.radio = null // no Web Audio: the timer still works
    }
    this.session = { round: 1, built: 0 }
    this.#round()
    this.ticker = setInterval(() => this.#tick(), 1000)
    this.#equalize()
    this.toggleTarget.focus()
  }

  toggle() {
    this.session.running = !this.session.running
    this.#render()
  }

  // Ends the round (or skips the break).
  end() {
    if (this.session.phase === "break") return this.#round()
    this.#finish()
  }

  again() {
    this.session.built = 0
    this.#round()
  }

  takeBreak() {
    Object.assign(this.session, { phase: "break", left: BREAK_SECONDS, total: BREAK_SECONDS, running: true })
    this.#render()
  }

  exit() {
    this.#stop()
    this.overlayTarget.hidden = true
    this.dispatch("exited")
  }

  key(event) {
    if (event.key === "Escape" && !this.overlayTarget.hidden) this.exit()
  }

  music() {
    if (!this.radio) return
    this.radio.playing ? this.radio.pause() : this.radio.play()
    setTimeout(() => this.#render(), 50)
  }

  nextTrack() {
    this.track = (this.track + 1) % TRACKS.length
    this.radio?.setTrack(this.track)
    this.#render()
  }

  // A round of focus, as long as your daily pace. The first is round 1; every one after counts up.
  #round() {
    const seconds = this.minutesValue * 60
    if (this.started) this.session.round += 1
    this.started = true
    Object.assign(this.session, { phase: "focus", left: seconds, total: seconds, running: true })
    this.#render()
  }

  #tick() {
    const session = this.session
    if (!session.running || session.phase === "done") return
    session.left -= 1
    if (session.phase === "focus") session.built += 1
    if (session.left > 0) return this.#render()
    session.phase === "focus" ? this.#finish() : this.#round()
  }

  #finish() {
    Object.assign(this.session, { phase: "done", running: false, left: 0 })
    if (this.radio?.playing) this.radio.chime()
    this.clippy.congratulate()
    this.#render()
  }

  #onBeat() {
    this.beat += 1
    const session = this.session
    const live = session?.running && this.radio?.playing
    this.clippyTarget.toggleAttribute("data-bob", Boolean(live && this.beat % 2))
    const pressed = [ (this.beat * 7) % KEYS, (this.beat * 3 + 5) % KEYS ]
    Array.from(this.keysTarget.children).forEach((key, index) =>
      key.toggleAttribute("data-pressed", Boolean(live && session.phase === "focus" && pressed.includes(index))))
    this.noteLeftTarget.toggleAttribute("data-up", this.beat % 2 === 0)
    this.noteRightTarget.toggleAttribute("data-up", this.beat % 2 === 1)
  }

  #equalize() {
    const bars = Array.from(this.equalizerTarget.children)
    const levels = this.radio ? this.radio.levels(bars.length) : bars.map(() => 0)
    bars.forEach((bar, index) => bar.style.blockSize = `${3 + levels[index] * 29}px`)
    this.frame = requestAnimationFrame(() => this.#equalize())
  }

  #render() {
    const { phase, running, round, built, left, total } = this.session
    const done = phase === "done"
    const onBreak = phase === "break"
    const playing = Boolean(this.radio?.playing)

    this.labelTarget.textContent = done ? "Session done" : onBreak ? "Break" : `${running ? "Focus" : "Paused"} · round ${round}`
    this.titleTarget.textContent = done ? (built < 60 ? "Short one. Every minute counts." : `Nice. ${Math.round(built / 60)} min of building.`)
      : onBreak ? "Stand up. Drink some water." : this.titleValue
    this.clockTarget.textContent = clock(done ? built : left)
    this.barTarget.style.inlineSize = done ? "100%" : `${(1 - left / total) * 100}%`
    this.barTarget.toggleAttribute("data-break", onBreak)
    this.noteTarget.textContent = done ? "Hackatime already logged it. Nothing to submit."
      : onBreak ? "Music keeps going. The next round starts on its own." : "Hackatime tracks your time on its own. This timer is just for focus."
    this.toggleLabelTarget.textContent = running ? "Pause" : "Resume"
    this.toggleTarget.setAttribute("aria-pressed", String(!running))
    this.endTarget.textContent = onBreak ? "Skip break" : "End session"
    this.liveTarget.hidden = done
    this.doneTarget.hidden = !done
    this.trackedTarget.textContent = `${hours(this.hoursLoggedValue + built / 3600)} of ${this.hoursGoalValue} hrs`
    this.overlayTarget.toggleAttribute("data-music", playing)

    const track = TRACKS[this.track]
    this.trackTagTarget.textContent = track.tag
    this.trackTagTarget.style.background = track.color
    this.trackNameTarget.textContent = track.name
    this.trackNumberTarget.textContent = `track ${this.track + 1} of ${TRACKS.length}`
    this.musicTarget.setAttribute("aria-pressed", String(playing))
    this.musicTarget.setAttribute("aria-label", playing ? "Pause music" : "Play music")
  }

  #stop() {
    clearInterval(this.ticker)
    cancelAnimationFrame(this.frame)
    this.radio?.close()
    this.radio = null
    this.started = false
  }
}

function clock(seconds) {
  const pad = (number) => String(number).padStart(2, "0")
  const h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60), s = seconds % 60
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

function hours(value) {
  return String(Math.round(value * 100) / 100)
}
