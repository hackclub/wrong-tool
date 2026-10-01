import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"
import { Radio, TRACKS } from "focus/radio"

const BREAK_SECONDS = 5 * 60
const KEYS = 22
// Hackatime's checked this often while you're locked in (and whenever you hit refresh).
const SYNC_EVERY = 3 * 60 * 1000
const LENGTH_KEY = "wrong-tool:pomodoro-minutes"
// Looking for a pomodoro your buddy started (on your project page), and who's in once you're in one together.
const BUDDY_WATCH_EVERY = 20 * 1000
const TOGETHER_POLL_EVERY = 10 * 1000

// A pomodoro: lock in for as long as you picked, over the whole page, with Wrong Tool Radio playing and Clippy at
// the keyboard, typing along while you work, idling when you pause and putting his feet up on a break. Your
// Hackatime hours along the top keep themselves up to date. When a round's done he congratulates you, and you
// can go again, take a five-minute break or head back.
export default class extends Controller {
  static targets = [ "overlay", "label", "title", "clock", "bar", "note", "toggle", "toggleLabel", "end", "live", "done",
                     "tracked", "sync", "synced", "clippy", "sprite", "keys", "noteLeft", "noteRight", "trackTag",
                     "trackName", "trackNumber", "equalizer", "music", "length", "together", "buddyLive", "buddyLiveText" ]
  static values = { title: String, hoursUrl: String, tracks: Object, sounds: Object, buddyUrl: String, buddyName: String }

  connect() {
    this.clippy = new Clippy(this.spriteTarget, this.soundsValue)
    this.track = 0
    this.keysTarget.innerHTML = "<span></span>".repeat(KEYS)
    this.equalizerTarget.innerHTML = "<span></span>".repeat(20)
    const saved = read(LENGTH_KEY)
    const remembered = this.lengthTargets.find((input) => input.value === saved)
    if (remembered) remembered.checked = true
    // With a buddy, keep an eye out for a pomodoro they start, to join.
    if (this.buddyUrlValue) this.watcher = setInterval(() => this.#checkBuddy(), BUDDY_WATCH_EVERY)
  }

  disconnect() {
    this.#stop()
    this.clippy.stop()
    clearInterval(this.watcher)
  }

  get minutes() {
    return Number(this.lengthTargets.find((input) => input.checked)?.value || 25)
  }

  pickLength() {
    write(LENGTH_KEY, String(this.minutes))
  }

  // On your own.
  start() {
    this.together = false
    this.#open()
  }

  // A pomodoro your buddy can join: started on the server, so you both count down to the same end.
  async startWithBuddy() {
    const status = await this.#buddyRequest("POST", this.buddyUrlValue, { minutes: this.minutes })
    if (status?.live) this.#openTogether(status)
  }

  async joinBuddy() {
    const status = await this.#buddyRequest("POST", `${this.buddyUrlValue}/join`)
    if (status?.live) this.#openTogether(status)
    else this.buddyLiveTarget.hidden = true
  }

  #openTogether(status) {
    this.together = true
    this.buddyLiveTarget.hidden = true
    const left = Math.max(1, Math.round((Date.parse(status.ends_at) - Date.parse(status.now)) / 1000))
    this.#open({ left, total: status.minutes * 60 })
    this.#showTogether(status)
    this.togetherPoll = setInterval(() => this.#checkBuddy(), TOGETHER_POLL_EVERY)
  }

  #open(timing) {
    this.#stop()
    this.overlayTarget.hidden = false
    try {
      this.radio = new Radio(this.tracksValue, () => this.#onBeat())
      this.radio.onTrack = () => this.#render()
      this.radio.setTrack(this.track)
      this.radio.play()
    } catch {
      this.radio = null // no Web Audio: the timer still works
    }
    this.session = { round: 1, built: 0 }
    this.#round(timing)
    this.ticker = setInterval(() => this.#tick(), 1000)
    this.syncer = setInterval(() => this.syncHours(), SYNC_EVERY)
    this.syncHours()
    this.#equalize()
    this.toggleTarget.focus()
  }

  toggle() {
    this.session.running = !this.session.running
    this.#feel()
    this.#render()
  }

  // Ends the round (or skips the break).
  end() {
    if (this.session.phase === "break") return this.#round()
    this.#finish()
  }

  again() {
    if (this.together) return this.startWithBuddy()
    this.session.built = 0
    this.#round()
  }

  takeBreak() {
    Object.assign(this.session, { phase: "break", left: BREAK_SECONDS, total: BREAK_SECONDS, running: true })
    this.#feel()
    this.#render()
  }

  exit() {
    this.#stop()
    this.overlayTarget.hidden = true
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

  // Asks for your hours from Hackatime (asking Hackatime itself when you hit refresh), spinning while it does.
  async syncHours(event) {
    if (this.syncing) return
    this.syncing = true
    this.syncTarget.toggleAttribute("data-syncing", true)
    try {
      const url = event ? `${this.hoursUrlValue}?refresh=1` : this.hoursUrlValue
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(response.statusText)
      const { label } = await response.json()
      this.trackedTarget.textContent = label
      this.syncedAt = Date.now()
      this.syncTarget.removeAttribute("data-failed")
    } catch {
      this.syncTarget.toggleAttribute("data-failed", true)
    } finally {
      this.syncing = false
      this.syncTarget.toggleAttribute("data-syncing", false)
      this.#renderSynced()
    }
  }

  // A round of focus, as long as you picked (or what's left of one with your buddy). The first is round 1; every one
  // after counts up.
  #round({ left, total } = {}) {
    const seconds = this.minutes * 60
    if (this.started) this.session.round += 1
    this.started = true
    Object.assign(this.session, { phase: "focus", left: left ?? seconds, total: total ?? seconds, running: true })
    this.#feel()
    this.#render()
  }

  #tick() {
    const session = this.session
    this.#renderSynced()
    if (!session.running || session.phase === "done") return
    session.left -= 1
    if (session.phase === "focus") session.built += 1
    if (session.left > 0) return this.#render()
    session.phase === "focus" ? this.#finish() : this.#round()
  }

  #finish() {
    Object.assign(this.session, { phase: "done", running: false, left: 0 })
    if (this.radio?.playing) this.radio.chime()
    this.clippy.feel("happy", { first: "Congratulate" })
    this.syncHours()
    this.#render()
  }

  // Typing while you work, idling when you pause, resting on a break.
  #feel() {
    const { phase, running } = this.session
    if (phase === "done") return
    this.clippy.feel(phase === "break" ? "resting" : running ? "typing" : "idle")
  }

  #onBeat() {
    this.beat = (this.beat || 0) + 1
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
    if (this.radio) this.track = this.radio.track

    const lockedIn = this.together ? `Locked in with ${this.buddyNameValue}` : "Locked in"
    this.labelTarget.textContent = done ? "Pomodoro done" : onBreak ? "Break" : `${running ? lockedIn : "Paused"} · round ${round}`
    this.titleTarget.textContent = done ? (built < 60 ? "Short one. Every minute counts." : `Nice. ${Math.round(built / 60)} min of building.`)
      : onBreak ? "Stand up. Drink some water." : this.titleValue
    this.clockTarget.textContent = clock(done ? built : left)
    this.barTarget.style.inlineSize = done ? "100%" : `${(1 - left / total) * 100}%`
    this.barTarget.toggleAttribute("data-break", onBreak)
    this.noteTarget.textContent = done ? "Hackatime already logged it. Nothing to submit."
      : onBreak ? "Music keeps going. The next round starts on its own." : ""
    this.noteTarget.hidden = !done && !onBreak
    this.toggleLabelTarget.textContent = running ? "Pause" : "Resume"
    this.toggleTarget.setAttribute("aria-pressed", String(!running))
    this.endTarget.textContent = onBreak ? "Skip break" : "End pomodoro"
    this.liveTarget.hidden = done
    this.doneTarget.hidden = !done
    this.overlayTarget.toggleAttribute("data-music", playing)

    const track = TRACKS[this.track]
    this.trackTagTarget.textContent = track.tag
    this.trackTagTarget.style.background = track.color
    this.trackNameTarget.textContent = track.name
    this.trackNumberTarget.textContent = `track ${this.track + 1} of ${TRACKS.length}`
    this.musicTarget.setAttribute("aria-pressed", String(playing))
    this.musicTarget.setAttribute("aria-label", playing ? "Pause music" : "Play music")
  }

  // "just now", "2 min ago", or that it couldn't.
  #renderSynced() {
    if (this.syncTarget.hasAttribute("data-failed")) return this.syncedTarget.textContent = "couldn't reach Hackatime"
    if (!this.syncedAt) return
    const minutes = Math.floor((Date.now() - this.syncedAt) / 60000)
    this.syncedTarget.textContent = minutes < 1 ? "just now" : `${minutes} min ago`
  }

  // How your buddy's pomodoro is going: whether there's one to join, or (in one together) whether they're in.
  async #checkBuddy() {
    const status = await this.#buddyRequest("GET", this.buddyUrlValue)
    if (!status) return
    if (this.together && !this.overlayTarget.hidden) return this.#showTogether(status)

    const waiting = status.live && !status.you_in
    this.buddyLiveTarget.hidden = !waiting
    if (waiting) this.buddyLiveTextTarget.textContent = `${status.buddy} started a ${status.minutes}-min pomodoro. Join in.`
  }

  #showTogether(status) {
    const name = status.buddy || this.buddyNameValue
    this.togetherTarget.hidden = false
    this.togetherTarget.toggleAttribute("data-in", Boolean(status.live && status.buddy_in))
    this.togetherTarget.textContent = !status.live ? `with ${name} · done` : status.buddy_in ? `with ${name} · in` : `waiting for ${name}`
  }

  async #buddyRequest(method, url, body) {
    try {
      const response = await fetch(url, {
        method,
        headers: { Accept: "application/json", "Content-Type": "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: body ? JSON.stringify(body) : undefined
      })
      return await response.json()
    } catch {
      return null
    }
  }

  #stop() {
    clearInterval(this.ticker)
    clearInterval(this.syncer)
    clearInterval(this.togetherPoll)
    if (this.hasTogetherTarget) this.togetherTarget.hidden = true
    cancelAnimationFrame(this.frame)
    this.radio?.close()
    this.radio = null
    this.started = false
    this.clippy?.stop()
  }
}

function clock(seconds) {
  const pad = (number) => String(number).padStart(2, "0")
  const h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60), s = seconds % 60
  return h ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

// localStorage can be off (private windows, blocked storage); then it just doesn't remember.
function read(key) {
  try { return localStorage.getItem(key) } catch { return null }
}

function write(key, value) {
  try { localStorage.setItem(key, value) } catch {}
}
