import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"
import { capture, previewing } from "analytics"

// The onboarding sheet: pick a wrong tool (A1), roll or write an idea (A2), pick a handheld (A3), then commit
// to a pace and sign the pledge it adds up to (A4). Tapping an answer moves on after a short flash; answered
// rows fold into cells that reopen them. Answers live in this tab (sessionStorage keeps them across the trip
// to Hack Club Auth), and the pledge signs itself once you're back.
const PICK_DELAY = 360
const ANSWERS_KEY = "wrong-tool:onboarding"
const ANSWERS = [ "step", "tool", "custom", "genre", "phrase", "twist", "idea", "ideaTool", "ideaOwn", "ideaSkipped", "prize",
                  "pace", "buildTime", "pledged", "signedOn" ]
// Set while the pledge is out being signed at Hack Club Auth, so coming back plays the ceremony.
const SIGNING_KEY = "wrong-tool:signing-pledge"
const STEP_NAMES = [ "tool", "idea", "prize", "commit" ]
// Holding the sign button: it fills over 1.3s (and signs when full); let go early and it runs back in 0.35s.
// A press shorter than `tap` ms shows how far a hold would get (`demo`) and says to hold; tap again and it fills
// by itself (`taps`).
const HOLD = { fill: 1300, rewind: 350, step: 30, tap: 260, demo: 0.25, taps: 2 }
// The signing ceremony, in 70ms ticks: the name finishes going on, Clippy congratulates you (hopping on the
// ticks in `hops`), the pledge counts as signed from the 6th tick and it's over after the 28th.
const CEREMONY = { tick: 70, signed: 6, ticks: 28, hops: [ 2, 5, 8 ] }

export default class extends Controller {
  static targets = [
    "row", "summary", "value",
    "tool", "otherName", "otherInput", "otherSubmit", "otherVerdict", "otherMood",
    "idea", "reel", "article", "dice", "rollLabel", "useIdea", "ownInput", "useOwn",
    "prize", "mascot", "mascotSprite", "mascotSay",
    "commit", "pace", "finishLine", "buildTime",
    "pledgePace", "pledgeEvery", "pledgeIdea", "pledgePreposition", "pledgeTool", "pledgeDate", "accountable", "pledgeTracker", "ink",
    "signature", "saveError",
    "signIn", "holdFill", "signInLabel", "signHint",
    "fileName", "progress", "nameBox", "formula", "projectTab"
  ]
  static values = {
    tools: Array, genres: Array, twists: Array, taken: Object, engines: Array, prizes: Array, hours: Number, sounds: Object,
    signedIn: Boolean, name: String, whoamiUrl: String, program: Object, checkIns: Object, codeNames: String,
    projectUrl: String, hasProject: Boolean
  }

  connect() {
    this.state = {
      step: 1, tool: null, custom: "", otherOpen: false,
      genre: "", phrase: "", twist: "", idea: "", ideaTool: null, ideaOwn: false, ideaSkipped: false,
      rolling: false, stop1: true, stop2: true, stop3: true, spin: 0, ownOpen: false, own: "",
      prize: null, pace: null, buildTime: null, pledged: false, signedOn: null, signing: false, signTick: -1,
      holdP: 0, holding: false, letGo: false, taps: 0, autofill: false,
      ...this.#restoreAnswers()
    }
    // A pledge is only signed for whoever's signed in, and only once it's saved as your project: without one (the
    // save failed, or the project's gone since), a pledge this tab remembers is there to sign again.
    if (!this.signedInValue || !this.hasProjectValue) this.state.pledged = false
    if (this.state.pledged) this.state.step = 4
    // Ideas rolled this visit (as the pledge would store them), so "Roll again" never shows one twice.
    this.rolled = new Set()
    this.clippy = new Clippy(this.mascotSpriteTarget, this.soundsValue)
    this.#render()
    this.#viewed()
    this.onPageHide = () => this.#abandoned()
    addEventListener("pagehide", this.onPageHide)
    this.#askWhoami()
    if (this.signedInValue && takeSigningFlag() && this.#commitReady()) {
      this.state.step = 4
      this.#render()
      this.ceremonyTimer = setTimeout(() => this.#signPledge(), 400)
    }
  }

  disconnect() {
    removeEventListener("pagehide", this.onPageHide)
    this.#abandoned()
    clearTimeout(this.pickTimer)
    clearTimeout(this.rollTimer)
    clearTimeout(this.mascotTimer)
    this.clippy.stop()
    clearTimeout(this.ceremonyTimer)
    clearInterval(this.ceremonyTicker)
    clearInterval(this.holdTicker)
    clearTimeout(this.hopTimer)
  }

  // An answered row, reopened.
  open({ params: { step } }) {
    this.#goTo(step)
  }

  // A1

  pickTool({ params: { tool } }) {
    const s = this.state
    if (tool === "other") {
      if (!s.otherOpen) {
        this.#did("other_opened")
        this.#set({ otherOpen: true })
      }
      this.otherInputTarget.focus()
      return
    }
    this.#set({ tool, otherOpen: false, ideaSkipped: s.tool === tool && s.ideaSkipped })
    this.#completed(1, { tool })
    this.#after(PICK_DELAY, () => this.#goTo(2))
  }

  typeOther({ target }) {
    this.#set({ custom: target.value })
  }

  otherKey(event) {
    if (event.key === "Escape") this.#set({ otherOpen: false })
  }

  confirmOther(event) {
    event?.preventDefault()
    const custom = this.state.custom.trim()
    if (!custom) return
    if (this.#verdict().kind === "engine") return this.#did("other_engine_blocked", { custom_tool: custom })
    this.#set({ tool: "other", otherOpen: false, ideaSkipped: false, ideaTool: null })
    this.#completed(1, { tool: "other", custom_tool: custom })
    this.#after(PICK_DELAY - 60, () => this.#goTo(2))
  }

  // A quick answer under Other: it's your tool.
  pickChip({ params: { name } }) {
    this.#did("other_chip_picked", { custom_tool: name })
    this.#set({ custom: name })
    this.confirmOther()
  }

  // Does what you typed under Other count? Anything does but a game engine (enginesValue). Says how its hours
  // would be tracked too. Clippy's feeling about it goes on its own line.
  #verdict() {
    const name = this.state.custom.trim()
    if (!name) return { kind: "none", text: "", mood: "" }
    const engines = new RegExp(`\\b(?:${this.enginesValue.map(escapeRegExp).join("|")})\\b`, "i")
    if (engines.test(name)) {
      return { kind: "engine", text: `${name}? That's a game engine, so it's the right tool. Pick something stranger.`,
               mood: "clippy is unmoved." }
    }
    const hours = this.#tracker() === "hackatime"
      ? "Hours come from the Hackatime plugin in your editor."
      : "Code in an editor counts through the Hackatime plugin. Everything else, record with Lapse."
    return { kind: "yes", text: `${name}? Yes, that counts. ${hours}`, mood: "clippy is intrigued." }
  }

  // A2. Three reels: the genre stops on its 11th tick, the tool's setting on its 16th and the twist on its 21st,
  // slowing down as they go. Where they land is decided up front (#pickIdea).

  roll(event) {
    if (this.state.rolling && !this.state.ownOpen) return
    if (event) this.#did("idea_rerolled")
    clearTimeout(this.rollTimer)
    const phrases = this.#phrases()
    const [ genre, twist ] = this.#pickIdea()
    const phrase = phrases.length > 1 ? pickOther(phrases, this.state.phrase) : phrases[0]
    const settle = () => ({ genre, phrase, twist, idea: ideaText(genre, phrase, twist), stop1: true, stop2: true, stop3: true,
                            rolling: false, ideaTool: this.state.tool, ideaOwn: false })

    this.#set({ rolling: true, stop1: false, stop2: false, stop3: false, ownOpen: false, ideaSkipped: false })
    if (reducedMotion()) return this.#set(settle())

    let tick = 0
    const spin = () => {
      tick++
      const s = this.state
      const changes = { spin: s.spin + 1 }
      if (!s.stop1) Object.assign(changes, tick >= 11 ? { genre, stop1: true } : { genre: any(this.genresValue) })
      if (!s.stop2) Object.assign(changes, tick >= 16 ? { phrase, stop2: true } : { phrase: any(phrases) })
      if (!s.stop3) Object.assign(changes, tick >= 21 ? settle() : { twist: any(this.twistsValue) })
      this.#set(changes)
      if (tick < 21) this.rollTimer = setTimeout(spin, 38 + tick * tick * 0.36)
    }
    spin()
  }

  // The genre and twist to land on. Both change from what's showing, and it's not one rolled this visit. Of
  // those, an idea nobody's pledged yet (takenValue counts pledges of each), or failing that one pledged just
  // once: at most two people end up building the same thing. Only once every idea's taken twice is any fair game.
  #pickIdea() {
    const s = this.state
    const pairs = this.genresValue.flatMap(genre => this.twistsValue.map(twist => [ genre, twist ]))
    const taken = ([ genre, twist ]) => this.takenValue[pledgeText(genre, twist)] ?? 0
    const untried = pairs.filter(([ genre, twist ]) => genre !== s.genre && twist !== s.twist && !this.rolled.has(pledgeText(genre, twist)))
    const pool = [ untried.filter(pair => taken(pair) === 0), untried.filter(pair => taken(pair) < 2), untried, pairs ].find(list => list.length)
    const pick = any(pool)
    this.rolled.add(pledgeText(...pick))
    return pick
  }

  useIdea() {
    if (this.state.rolling || !this.state.idea) return
    this.#completed(2, { idea_source: this.state.ideaOwn ? "own" : "rolled" })
    this.#afterIdea()
  }

  openOwn() {
    clearTimeout(this.rollTimer)
    const s = this.state
    this.#did("own_idea_opened")
    this.#set({ ownOpen: true, rolling: false, stop1: true, stop2: true, stop3: true, own: s.ideaOwn ? s.idea : s.own })
    this.ownInputTarget.focus()
  }

  closeOwn() {
    this.#did("own_idea_closed")
    this.#set({ ownOpen: false })
    if (!this.state.idea || this.state.ideaOwn) this.roll()
  }

  typeOwn({ target }) {
    this.#set({ own: target.value })
  }

  useOwn(event) {
    event.preventDefault()
    const own = this.state.own.trim()
    if (!own) return
    this.#set({ idea: own, ideaOwn: true, ideaSkipped: false, ownOpen: false, ideaTool: this.state.tool })
    this.#completed(2, { idea_source: "own" })
    this.#afterIdea()
  }

  skipIdea() {
    clearTimeout(this.rollTimer)
    this.#set({ ideaSkipped: true, idea: "", genre: "", phrase: "", twist: "", rolling: false, stop1: true, stop2: true, stop3: true,
                ideaOwn: false })
    this.#completed(2, { idea_source: "skipped" })
    this.#afterIdea()
  }

  // A3. Picking a handheld moves straight on; the mascot pops up to congratulate you on the way.

  claim({ params: { prize } }) {
    this.#set({ prize })
    this.#completed(3, { prize })
    const { name } = this.prizesValue.find(({ id }) => id === prize)
    this.#congratulate(`Nice pick! The ${name} is yours after ${this.hoursValue} hours.`)
    this.#goTo(4)
  }

  // A4. Nothing's picked until you pick it.

  pickPace({ target }) {
    this.#set({ pace: Number(target.value) })
    this.#did("pace_picked", { pace_minutes: this.state.pace })
    this.#hop()
  }

  pickBuildTime({ target }) {
    this.#set({ buildTime: target.value })
    this.#did("build_time_picked", { build_time: target.value })
    this.#hop()
  }

  // Back (from Hack Club Auth, say) to a page the browser kept as it was: the button is ready to try again.
  resume({ persisted }) {
    if (persisted) this.left = false
    if (persisted && this.state.signing) this.#set({ signing: false, holdP: 0 })
  }

  // Hold to sign: pressing fills the button, and the signature goes on with it. Full means signed.
  holdStart(event) {
    const s = this.state
    if (!this.#commitReady() || s.signing || s.pledged || s.signTick >= 0 || s.holding) return
    if (event.pointerId != null) {
      if (event.button !== 0) return
      try { event.currentTarget.setPointerCapture(event.pointerId) } catch {}
    }
    this.#did("hold_started")
    this.holdSince = performance.now()
    this.#set({ holding: true, letGo: false })
    this.#tickHold(HOLD.step / HOLD.fill, () => this.#finishHold())
  }

  // Letting go early runs it back. A tap (as if it were an ordinary button) runs a little way first, to show what
  // holding does; the second tap means holding isn't working for you, so it fills and signs by itself.
  holdEnd() {
    const s = this.state
    if (!s.holding || s.autofill) return
    const progress = Math.round(s.holdP * 100)
    const tapped = performance.now() - this.holdSince < HOLD.tap
    const taps = s.taps + (tapped ? 1 : 0)
    this.#did(tapped ? "sign_tapped" : "hold_let_go_early", { progress_percent: progress, taps })
    if (tapped && taps >= HOLD.taps) {
      this.#did("sign_autofilled", { taps })
      return this.#set({ taps, autofill: true })
    }
    this.#set({ holding: false, letGo: s.holdP > 0.05 || tapped, taps })
    if (tapped && s.holdP < HOLD.demo) {
      this.#tickHold(HOLD.step / HOLD.fill, null, HOLD.demo, () => this.#tickHold(-HOLD.step / HOLD.rewind))
    } else {
      this.#tickHold(-HOLD.step / HOLD.rewind)
    }
  }

  // Space or Enter can be held too.
  holdKey(event) {
    if (event.key !== " " && event.key !== "Enter") return
    event.preventDefault()
    if (!event.repeat) this.holdStart(event)
  }

  holdKeyEnd(event) {
    if (event.key === " " || event.key === "Enter") this.holdEnd()
  }

  // A click (or a long press's menu) isn't a hold, so it doesn't submit anything.
  holdClick(event) {
    event.preventDefault()
  }

  // Flow

  #goTo(step) {
    clearTimeout(this.pickTimer)
    const moved = step !== this.state.step
    this.#set({ step, otherOpen: false })
    if (moved) this.#viewed()
    const s = this.state
    if (step === 2 && !s.ideaSkipped && (!s.idea || (s.ideaTool !== s.tool && !s.ideaOwn))) this.roll()
    this.rowTargets[step - 1].querySelector("h2").focus({ preventScroll: true })
  }

  // For PostHog. Each step is onboarding_step_viewed when you get to it, onboarding_action for what you try
  // there, and onboarding_step_completed (1, tool, to 4, commit: the hold that signs in) once it's answered.
  // Leaving before the pledge is signed is onboarding_abandoned, with where you were and what you did last.
  #completed(step, properties, options) {
    this.lastAction = "completed"
    capture("onboarding_step_completed", { step, step_name: STEP_NAMES[step - 1], ...properties }, options)
  }

  #viewed() {
    const { step, pledged } = this.state
    if (pledged || previewing()) return
    Object.assign(this, { stepSince: performance.now(), furthestStep: Math.max(this.furthestStep ?? 0, step) })
    capture("onboarding_step_viewed", { step, step_name: STEP_NAMES[step - 1] })
  }

  #did(action, properties = {}) {
    this.lastAction = action
    const { step } = this.state
    capture("onboarding_action", { action, step, step_name: STEP_NAMES[step - 1], ...properties })
  }

  // Off to Hack Club Auth, or done, isn't leaving.
  #abandoned() {
    const s = this.state
    if (this.left || this.stepSince == null || s.signing || s.pledged || s.signTick >= 0) return
    this.left = true
    capture("onboarding_abandoned", {
      step: s.step, step_name: STEP_NAMES[s.step - 1], furthest_step: this.furthestStep,
      seconds_on_step: Math.round((performance.now() - this.stepSince) / 1000), last_action: this.lastAction ?? null
    }, { transport: "sendBeacon" })
  }

  #afterIdea() {
    this.#goTo(this.state.prize ? 4 : 3)
  }

  // Moves the hold along by `delta` a step until it's full (then `full`) or empty, or, given `stop`, until it
  // gets that far (then `stopped`).
  #tickHold(delta, full, stop, stopped) {
    clearInterval(this.holdTicker)
    this.holdTicker = setInterval(() => {
      const holdP = Math.min(stop ?? 1, Math.max(0, this.state.holdP + delta))
      this.#set({ holdP })
      if (stop != null && holdP === stop) {
        clearInterval(this.holdTicker)
        return stopped?.()
      }
      if (holdP === 1 || holdP === 0) clearInterval(this.holdTicker)
      if (holdP === 1) full?.()
    }, HOLD.step)
  }

  // Signing the pledge is signing in. Already signed in, it signs right here; otherwise the form goes to Hack
  // Club Auth, and the answers wait in this tab for the trip back.
  #finishHold() {
    this.#set({ holding: false, autofill: false })
    const s = this.state
    this.#completed(4, { pace_minutes: s.pace, build_time: s.buildTime, signed_in: this.signedInValue },
                    { transport: "sendBeacon" })
    if (this.signedInValue) return this.#signPledge()

    this.#saveAnswers()
    try { sessionStorage.setItem(SIGNING_KEY, "true") } catch {}
    this.#set({ signing: true })
    this.signInTarget.form.submit()
  }

  // Signed in to Hack Club but not to us yet? Hack Club Auth's whoami tells us your first name, so the pledge
  // is signed in it as you hold. Anything else (not signed in there, or not allowed from here) leaves it unsigned.
  async #askWhoami() {
    if (!this.whoamiUrlValue) return
    try {
      const response = await fetch(this.whoamiUrlValue, { credentials: "include" })
      const { signed_in: signedIn, first_name: firstName } = await response.json()
      if (signedIn && firstName) {
        this.hackClubName = firstName
        this.#render()
      }
    } catch {}
  }

  #signerName() {
    return this.nameValue || this.hackClubName || ""
  }

  #hop() {
    clearTimeout(this.hopTimer)
    this.mascotTarget.toggleAttribute("data-hop", true)
    this.hopTimer = setTimeout(() => this.mascotTarget.toggleAttribute("data-hop", false), 170)
  }

  #commitReady(s = this.state) {
    return !!(s.tool && s.prize && s.pace && s.buildTime)
  }

  // The ceremony (see CEREMONY). With reduced motion, it's simply signed (and Clippy still says so).
  #signPledge() {
    const signedOn = isoDate(new Date())
    if (reducedMotion()) {
      this.#set({ pledged: true, signing: false, signedOn })
      this.#congratulate(`Signed. I'll check in ${this.checkInsValue[this.state.buildTime]} to keep you on track.`)
      this.#showDayOne()
      this.#saveAnswers()
      return this.saveProject()
    }

    this.#set({ signing: false, signTick: 0, signedOn, holdP: 1 })
    this.#congratulate(`Signed. I'll check in ${this.checkInsValue[this.state.buildTime]} to keep you on track.`)
    clearInterval(this.ceremonyTicker)
    this.ceremonyTicker = setInterval(() => {
      const tick = this.state.signTick + 1
      if (CEREMONY.hops.includes(tick)) this.#hop()
      if (tick === CEREMONY.signed) {
        this.state.pledged = true
        this.#saveAnswers()
      }
      if (tick > CEREMONY.ticks) {
        clearInterval(this.ceremonyTicker)
        this.#set({ signTick: -1 })
        return this.saveProject()
      }
      this.#set({ signTick: tick })
      if (tick === CEREMONY.signed) this.#showDayOne()
    }, CEREMONY.tick)
  }

  // The signed pledge becomes your project, and off you go to it. (Try again, if it didn't save.) If you'd already
  // pledged, your project stays as it was.
  async saveProject() {
    const s = this.state
    this.saveErrorTarget.hidden = true
    const project = { tool: s.tool, tool_name: this.#toolName(), idea: this.#pledgeIdea(), prize: s.prize,
                      pace_minutes: s.pace, build_time: s.buildTime }
    try {
      const response = await fetch(this.projectUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json",
                   "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content },
        body: JSON.stringify({ project })
      })
      if (!response.ok) throw new Error(`Saving the pledge: ${response.status}`)
      const { location } = await response.json()
      // Anything Turbo kept of the project from before it existed was the redirect back here.
      window.Turbo?.cache.clear()
      window.Turbo ? window.Turbo.visit(location) : window.location.assign(location)
    } catch (error) {
      this.#did("pledge_save_failed", { error: String(error.message ?? error) })
      this.saveErrorTarget.hidden = false
    }
  }

  // "Day 1 starts now." can land below the fold on a short screen; bring it up.
  #showDayOne() {
    this.commitTarget.querySelector(".onboarding-commit__signed")
      .scrollIntoView({ block: "nearest", behavior: reducedMotion() ? "auto" : "smooth" })
  }

  // The day you'd log your last hour: sessions of `pace` minutes, one a day (only Saturdays and Sundays if you
  // build on weekends), from the day wrong tool starts, or today if that's later.
  #finishDate(s = this.state) {
    if (!s.pace) return null
    let sessions = Math.ceil((this.hoursValue * 60) / s.pace)
    const today = new Date()
    const day = new Date(Math.max(localDate(this.programValue.start), new Date(today.getFullYear(), today.getMonth(), today.getDate())))
    for (;;) {
      if (s.buildTime !== "weekends" || [ 0, 6 ].includes(day.getDay())) sessions--
      if (sessions <= 0) return day
      day.setDate(day.getDate() + 1)
    }
  }

  // What the pledge says you'll ship: the genre and twist you rolled (the tool comes after "in"), what you wrote,
  // or something cursed if you skipped.
  #pledgeIdea(s = this.state) {
    if (!s.idea) return "something cursed"
    if (!s.ideaOwn && s.genre) return pledgeText(s.genre, s.twist)
    return s.idea
  }

  // Clippy, perched on the pledge, congratulates you, saying `message` if there is one (it stays up a little
  // after he's done). Another reason to congratulate you starts him over.
  #congratulate(message = "") {
    clearTimeout(this.mascotTimer)
    this.mascotSayTarget.textContent = message
    this.clippy.congratulate(() => {
      this.mascotTimer = setTimeout(() => { this.mascotSayTarget.textContent = "" }, 1200)
    })
  }

  #after(delay, callback) {
    clearTimeout(this.pickTimer)
    this.pickTimer = setTimeout(callback, delay)
  }

  #set(changes) {
    Object.assign(this.state, changes)
    this.#render()
  }

  #tool(s = this.state) {
    return this.toolsValue.find(tool => tool.id === s.tool)
  }

  #toolName(s = this.state) {
    const tool = this.#tool(s)
    if (!tool) return ""
    return tool.id === "other" ? (s.custom.trim() || "Other") : tool.name
  }

  // Where the hours will come from: the tool's tracker, or for Other, the Hackatime plugin if the name sounds like
  // code (Project::CODE_NAMES) and Lapse otherwise.
  #tracker() {
    const tool = this.#tool()
    if (tool?.tracker) return tool.tracker
    return new RegExp(this.codeNamesValue, "i").test(this.state.custom) ? "hackatime" : "lapse"
  }

  #phrases() {
    const tool = this.#tool()
    if (!tool) return [ "in the wrong tool" ]
    if (tool.id !== "other") return tool.phrases
    const name = this.state.custom.trim() || "your tool"
    return [ `in ${name}`, `built inside ${name}`, `that only runs in ${name}`, `where ${name} is the engine` ]
  }

  #saveAnswers() {
    const answers = Object.fromEntries(ANSWERS.map(key => [ key, this.state[key] ]))
    try { sessionStorage.setItem(ANSWERS_KEY, JSON.stringify(answers)) } catch {}
  }

  #restoreAnswers() {
    try {
      const answers = JSON.parse(sessionStorage.getItem(ANSWERS_KEY)) ?? {}
      return Object.fromEntries(ANSWERS.filter(key => key in answers).map(key => [ key, answers[key] ]))
    } catch {
      return {}
    }
  }

  // Drawing

  #render() {
    const s = this.state
    const tool = this.#tool()
    const toolName = this.#toolName()
    const prize = this.prizesValue.find(prize => prize.id === s.prize)
    const finish = this.#finishDate()
    const done = { 1: !!s.tool, 2: !!s.idea || s.ideaSkipped, 3: !!prize, 4: s.pledged }
    const values = {
      1: toolName,
      2: s.idea ? capitalize(s.idea) : s.ideaSkipped ? "Not decided yet" : "",
      3: prize?.full ?? "",
      4: s.pledged && finish ? `Signed · done by ${shortDate(finish)}` : ""
    }

    this.rowTargets.forEach((row, index) => {
      const step = index + 1
      const active = step === s.step
      const later = step === 2 && s.ideaSkipped && !s.idea
      row.dataset.state = active ? "active" : done[step] ? "done" : "locked"
      this.summaryTargets[index].disabled = active || !done[step]
      this.valueTargets[index].textContent = values[step]
      this.valueTargets[index].classList.toggle("onboarding-row__value--later", later)
    })

    this.#renderTools()
    this.#renderIdea(toolName)
    this.#renderPrizes()
    this.#renderCommit(toolName, finish)

    const slug = s.idea ? s.idea.replace(/^(a|an) /i, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 36) : "untitled_game"
    this.fileNameTarget.textContent = tool ? slug + tool.extension : "untitled_wrong_game"
    this.progressTarget.textContent = s.pledged ? "Day 1" : `Step ${s.step} of 4`
    this.nameBoxTarget.textContent = `A${s.step}`
    this.formulaTarget.textContent = this.#formula(toolName, finish)
    this.element.toggleAttribute("data-saved", s.pledged)
    this.projectTabTarget.setAttribute("aria-disabled", !(s.pledged || this.hasProjectValue))
  }

  #formula(toolName, finish) {
    const s = this.state
    switch (s.step) {
      case 1: return s.otherOpen ? `=PICK("${s.custom || "…"}")` : s.tool ? `=PICK("${toolName}")` : "=PICK(platform)"
      case 2:
        if (s.rolling) return `=IDEA(RAND(), "${toolName}")`
        if (s.ownOpen) return `="${s.own}"`
        return s.idea ? `="${s.idea}"` : `=IDEA(RAND(), "${toolName}")`
      case 3: return `=PRIZE(${this.hoursValue} hrs)`
      default: {
        const idea = this.#pledgeIdea().replace(/^(a|an) /i, "")
        const date = finish ? `DATE(${finish.getMonth() + 1},${finish.getDate()})` : "DATE(?,?)"
        const ship = `=SHIP("${idea}","${toolName || "?"}",${date})`
        return s.pledged ? `${ship} → TRUE` : s.signing ? `${ship} → #LOADING` : ship
      }
    }
  }

  #renderTools() {
    const s = this.state
    this.toolTargets.forEach(tile => {
      const id = tile.dataset.tool
      const selected = s.tool === id && !s.otherOpen
      tile.toggleAttribute("data-selected", selected)
      tile.toggleAttribute("data-editing", id === "other" && s.otherOpen)
      tile.querySelector("button").setAttribute("aria-pressed", selected)
    })
    this.otherNameTarget.textContent = s.tool === "other" && s.custom.trim() ? s.custom.trim() : "Other"
    if (this.otherInputTarget.value !== s.custom) this.otherInputTarget.value = s.custom
    const verdict = this.#verdict()
    this.otherVerdictTarget.textContent = verdict.text
    this.otherVerdictTarget.dataset.kind = verdict.kind
    this.otherMoodTarget.textContent = verdict.mood
    this.otherSubmitTarget.disabled = verdict.kind === "engine"
  }

  #renderIdea(toolName) {
    const s = this.state
    const tool = this.#tool()
    const [ genreReel, phraseReel, twistReel ] = this.reelTargets
    this.ideaTarget.dataset.mode = s.ownOpen ? "own" : "roll"
    this.articleTarget.textContent = s.genre ? article(s.genre) : "a"
    genreReel.textContent = s.genre || "…"
    genreReel.toggleAttribute("data-spinning", !s.stop1)
    phraseReel.textContent = s.phrase || "…"
    phraseReel.toggleAttribute("data-spinning", !s.stop2)
    twistReel.textContent = s.twist || "…"
    twistReel.toggleAttribute("data-spinning", !s.stop3)
    this.diceTarget.style.rotate = `${s.spin * 90}deg`
    this.rollLabelTarget.textContent = s.rolling ? "Rolling…" : "Roll again"
    this.useIdeaTarget.disabled = s.rolling || !s.idea

    if (this.ownInputTarget.value !== s.own) this.ownInputTarget.value = s.own
    this.ownInputTarget.placeholder = `a heist game ${tool && tool.id !== "other" ? tool.phrases[0] : `in ${toolName}`}`
    this.useOwnTarget.disabled = !s.own.trim()
  }

  #renderPrizes() {
    const s = this.state
    this.prizeTargets.forEach(card => {
      const claimed = card.dataset.prize === s.prize
      card.toggleAttribute("data-claimed", claimed)
      card.setAttribute("aria-pressed", claimed)
    })
  }

  #renderCommit(toolName, finish) {
    const s = this.state
    const busy = s.pledged || s.signing || s.signTick >= 0 || s.holding
    this.paceTargets.forEach(input => { input.checked = Number(input.value) === s.pace; input.disabled = busy })
    this.buildTimeTargets.forEach(input => { input.checked = input.value === s.buildTime; input.disabled = busy })

    // "You'd finish by Oct 15." (and a word if that's after wrong tool ends)
    const end = localDate(this.programValue.end)
    const late = finish && finish > end
    this.finishLineTarget.replaceChildren(...(finish
      ? [ "You'd finish by ", Object.assign(document.createElement("b"), { textContent: shortDate(finish) }), ".",
          late ? ` That's after wrong tool ends on ${shortDate(end)}.` : "" ]
      : []))
    this.finishLineTarget.toggleAttribute("data-late", !!late)

    // The pledge
    const tool = this.#tool()
    fill(this.pledgeIdeaTarget, this.#pledgeIdea())
    this.pledgePrepositionTarget.textContent = tool?.preposition ?? "in"
    fill(this.pledgeToolTarget, toolName || "the wrong tool")
    fill(this.pledgeDateTarget, finish && shortDate(finish), "\u2003\u2003\u2003")
    fill(this.pledgePaceTarget, this.paceTargets.find(input => Number(input.value) === s.pace)?.dataset.label, "\u2003\u2003\u2003")
    this.pledgeEveryTarget.textContent = s.buildTime === "weekends" ? "every weekend day" : "every day"
    const checkIn = this.checkInsValue[s.buildTime]
    this.accountableTarget.textContent = `Clippy will check in${checkIn ? ` ${checkIn}` : ""} to keep you on track.`
    this.pledgeTrackerTarget.textContent = this.#tracker() === "hackatime"
      ? "Hours come from the Hackatime plugin in your editor."
      : "Hours come from Lapse recordings, or the Hackatime plugin for any code you write in an editor."

    // The signature goes on as you hold (your name, if Hack Club's told us it), and finishes in the ceremony.
    const name = this.#signerName()
    const ceremony = s.signTick >= 0
    const ink = s.pledged || s.signing || ceremony ? 1 : s.holdP
    const written = ceremony ? Math.max(Math.ceil(s.holdP * name.length), s.signTick + 1) : Math.ceil(ink * name.length)
    this.signatureTarget.textContent = name.slice(0, written)
    this.inkTarget.style.inlineSize = `${ink * 100}%`
    this.commitTarget.toggleAttribute("data-inked", ink > 0)
    this.commitTarget.toggleAttribute("data-pledged", s.pledged)

    // The button fills as you hold it.
    const ready = this.#commitReady()
    this.signInTarget.disabled = !ready || (busy && !s.holding)
    this.signInTarget.toggleAttribute("data-holding", s.holding)
    this.signInTarget.toggleAttribute("data-signing", s.signing)
    this.signInTarget.setAttribute("aria-busy", s.signing)
    this.holdFillTarget.style.inlineSize = `${(s.signing || ceremony ? 1 : s.holdP) * 100}%`
    this.signInLabelTarget.textContent = s.signing ? "Signing in with Hack Club…"
      : s.autofill ? "Signing…"
      : s.holding ? "Keep holding…"
      : s.taps ? "Press and hold to sign"
      : "Hold to sign with Hack Club"
    this.signHintTarget.textContent = s.signing ? "Your pledge is tied to your Hack Club account."
      : !s.pace && !s.buildTime ? "Answer both to sign."
      : !s.pace ? "Pick a pace first."
      : !s.buildTime ? "Pick a time first."
      : s.autofill ? "No need to hold. Signing it for you."
      : s.letGo && s.taps ? "Keep it pressed until it fills, about a second. Or tap once more."
      : s.letGo ? "Almost. Hold until it's signed."
      : this.#signerName() ? "Holding signs your name to this pledge."
      : "Hold, then sign in with Hack Club to finish."
  }
}

function any(list) {
  return list[Math.floor(Math.random() * list.length)]
}

function pickOther(list, current) {
  let pick = any(list)
  while (list.length > 1 && pick === current) pick = any(list)
  return pick
}

function article(word) {
  return /^[aeiou]/i.test(word) ? "an" : "a"
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// "a snake clone in Google Sheets, where the floor is lava": what the reels read together.
function ideaText(genre, phrase, twist) {
  return `${article(genre)} ${genre} ${phrase}, ${twist}`
}

// "a snake clone where the floor is lava": what the pledge stores (the tool follows "in"). Answers saved before
// there were twists have none.
function pledgeText(genre, twist) {
  return [ article(genre), genre, twist ].filter(Boolean).join(" ")
}

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

// A blank in the pledge: the answer, or what it's waiting on.
function fill(blank, answer, placeholder = "") {
  blank.textContent = answer || placeholder
  blank.toggleAttribute("data-empty", !answer)
}

// "2026-10-02" as that day in local time (new Date() would read it as UTC midnight).
function localDate(iso) {
  const [ year, month, day ] = iso.split("-").map(Number)
  return new Date(year, month - 1, day)
}

// "Oct 15"
function shortDate(date) {
  return date.toLocaleDateString("en-US", { month: "short", day: "numeric" })
}

// Today (or any day) as "2026-09-30", in local time.
function isoDate(date) {
  return [ date.getFullYear(), date.getMonth() + 1, date.getDate() ].map(part => String(part).padStart(2, "0")).join("-")
}


// Whether we just came back from signing the pledge at Hack Club Auth. Reading it clears it.
function takeSigningFlag() {
  try {
    const signing = sessionStorage.getItem(SIGNING_KEY) === "true"
    sessionStorage.removeItem(SIGNING_KEY)
    return signing
  } catch {
    return false
  }
}

function reducedMotion() {
  return matchMedia("(prefers-reduced-motion: reduce)").matches
}
