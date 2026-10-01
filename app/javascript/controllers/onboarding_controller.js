import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"

// The onboarding sheet: pick a wrong tool (A1), roll or write an idea (A2), pick a handheld (A3), then commit
// to a pace and sign the pledge it adds up to (A4). Tapping an answer moves on after a short flash; answered
// rows fold into cells that reopen them. Answers live in this tab (sessionStorage keeps them across the trip
// to Hack Club Auth), and the pledge signs itself once you're back.
const PICK_DELAY = 360
const ANSWERS_KEY = "wrong-tool:onboarding"
const ANSWERS = [ "step", "tool", "custom", "genre", "phrase", "idea", "ideaTool", "ideaOwn", "ideaSkipped", "prize",
                  "pace", "buildTime", "pledged", "signedOn" ]
// Set while the pledge is out being signed at Hack Club Auth, so coming back plays the ceremony.
const SIGNING_KEY = "wrong-tool:signing-pledge"
// Holding the sign button: it fills over 1.3s (and signs when full); let go early and it runs back in 0.35s.
const HOLD = { fill: 1300, rewind: 350, step: 30 }
// The signing ceremony, in 70ms ticks: the name finishes going on, Clippy congratulates you (hopping on the
// ticks in `hops`), the pledge counts as signed from the 6th tick and it's over after the 28th.
const CEREMONY = { tick: 70, signed: 6, ticks: 28, hops: [ 2, 5, 8 ] }

export default class extends Controller {
  static targets = [
    "row", "summary", "value",
    "tool", "otherName", "otherInput",
    "idea", "reel", "article", "dice", "rollLabel", "useIdea", "ownInput", "useOwn",
    "prize", "mascot", "mascotSprite", "mascotSay",
    "commit", "pace", "finishLine", "buildTime",
    "pledgePace", "pledgeEvery", "pledgeIdea", "pledgePreposition", "pledgeTool", "pledgeDate", "accountable", "ink",
    "signature", "saveError",
    "signIn", "holdFill", "signInLabel", "signHint",
    "fileName", "progress", "nameBox", "formula", "projectTab"
  ]
  static values = {
    tools: Array, genres: Array, prizes: Array, hours: Number, sounds: Object,
    signedIn: Boolean, name: String, whoamiUrl: String, program: Object, checkIns: Object,
    projectUrl: String, hasProject: Boolean
  }

  connect() {
    this.state = {
      step: 1, tool: null, custom: "", otherOpen: false,
      genre: "", phrase: "", idea: "", ideaTool: null, ideaOwn: false, ideaSkipped: false,
      rolling: false, stop1: true, stop2: true, spin: 0, ownOpen: false, own: "",
      prize: null, pace: null, buildTime: null, pledged: false, signedOn: null, signing: false, signTick: -1,
      holdP: 0, holding: false, letGo: false,
      ...this.#restoreAnswers()
    }
    // A pledge is only signed for whoever's signed in.
    if (!this.signedInValue) this.state.pledged = false
    if (this.state.pledged) this.state.step = 4
    this.clippy = new Clippy(this.mascotSpriteTarget, this.soundsValue)
    this.#render()
    this.#askWhoami()
    if (this.signedInValue && takeSigningFlag() && this.#commitReady()) {
      this.state.step = 4
      this.#render()
      this.ceremonyTimer = setTimeout(() => this.#signPledge(), 400)
    }
  }

  disconnect() {
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
      if (!s.otherOpen) this.#set({ otherOpen: true })
      this.otherInputTarget.focus()
      return
    }
    this.#set({ tool, otherOpen: false, ideaSkipped: s.tool === tool && s.ideaSkipped })
    this.#after(PICK_DELAY, () => this.#goTo(2))
  }

  typeOther({ target }) {
    this.#set({ custom: target.value })
  }

  otherKey(event) {
    if (event.key === "Escape") this.#set({ otherOpen: false })
  }

  confirmOther(event) {
    event.preventDefault()
    if (!this.state.custom.trim()) return
    this.#set({ tool: "other", otherOpen: false, ideaSkipped: false, ideaTool: null })
    this.#after(PICK_DELAY - 60, () => this.#goTo(2))
  }

  // A2. The genre reel stops on its 13th tick and the setting on its 21st, slowing down as they go.

  roll() {
    if (this.state.rolling && !this.state.ownOpen) return
    clearTimeout(this.rollTimer)
    const phrases = this.#phrases()
    const genre = pickOther(this.genresValue, this.state.genre)
    const phrase = phrases.length > 1 ? pickOther(phrases, this.state.phrase) : phrases[0]
    const settle = () => ({ genre, phrase, idea: `${article(genre)} ${genre} ${phrase}`, stop1: true, stop2: true,
                            rolling: false, ideaTool: this.state.tool, ideaOwn: false })

    this.#set({ rolling: true, stop1: false, stop2: false, ownOpen: false, ideaSkipped: false })
    if (reducedMotion()) return this.#set(settle())

    let tick = 0
    const spin = () => {
      tick++
      const s = this.state
      const changes = { spin: s.spin + 1 }
      if (!s.stop1) Object.assign(changes, tick >= 13 ? { genre, stop1: true } : { genre: any(this.genresValue) })
      if (!s.stop2) Object.assign(changes, tick >= 21 ? settle() : { phrase: any(phrases) })
      this.#set(changes)
      if (tick < 21) this.rollTimer = setTimeout(spin, 38 + tick * tick * 0.36)
    }
    spin()
  }

  useIdea() {
    if (!this.state.rolling && this.state.idea) this.#afterIdea()
  }

  openOwn() {
    clearTimeout(this.rollTimer)
    const s = this.state
    this.#set({ ownOpen: true, rolling: false, stop1: true, stop2: true, own: s.ideaOwn ? s.idea : s.own })
    this.ownInputTarget.focus()
  }

  closeOwn() {
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
    this.#afterIdea()
  }

  skipIdea() {
    clearTimeout(this.rollTimer)
    this.#set({ ideaSkipped: true, idea: "", genre: "", phrase: "", rolling: false, stop1: true, stop2: true, ideaOwn: false })
    this.#afterIdea()
  }

  // A3. Picking a handheld moves straight on; the mascot pops up to congratulate you on the way.

  claim({ params: { prize } }) {
    this.#set({ prize })
    const { name } = this.prizesValue.find(({ id }) => id === prize)
    this.#congratulate(`Nice pick! The ${name} is yours after ${this.hoursValue} hours.`)
    this.#goTo(4)
  }

  // A4. Nothing's picked until you pick it.

  pickPace({ target }) {
    this.#set({ pace: Number(target.value) })
    this.#hop()
  }

  pickBuildTime({ target }) {
    this.#set({ buildTime: target.value })
    this.#hop()
  }

  // Back (from Hack Club Auth, say) to a page the browser kept as it was: the button is ready to try again.
  resume({ persisted }) {
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
    this.#set({ holding: true, letGo: false })
    this.#tickHold(HOLD.step / HOLD.fill, () => this.#finishHold())
  }

  // Letting go early runs it back.
  holdEnd() {
    if (!this.state.holding) return
    this.#set({ holding: false, letGo: this.state.holdP > 0.05 })
    this.#tickHold(-HOLD.step / HOLD.rewind)
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
    this.#set({ step, otherOpen: false })
    const s = this.state
    if (step === 2 && !s.ideaSkipped && (!s.idea || (s.ideaTool !== s.tool && !s.ideaOwn))) this.roll()
    this.rowTargets[step - 1].querySelector("h2").focus({ preventScroll: true })
  }

  #afterIdea() {
    this.#goTo(this.state.prize ? 4 : 3)
  }

  // Moves the hold along by `delta` a step until it's full (then `full`) or empty.
  #tickHold(delta, full) {
    clearInterval(this.holdTicker)
    this.holdTicker = setInterval(() => {
      const holdP = Math.min(1, Math.max(0, this.state.holdP + delta))
      this.#set({ holdP })
      if (holdP === 1 || holdP === 0) clearInterval(this.holdTicker)
      if (holdP === 1) full?.()
    }, HOLD.step)
  }

  // Signing the pledge is signing in. Already signed in, it signs right here; otherwise the form goes to Hack
  // Club Auth, and the answers wait in this tab for the trip back.
  #finishHold() {
    this.#set({ holding: false })
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

  // The signed pledge becomes your project, and off you go to it. (Try again, if it didn't save.)
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
    } catch {
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

  // What the pledge says you'll ship: the genre you rolled (the tool comes after "in"), what you wrote, or
  // something cursed if you skipped.
  #pledgeIdea(s = this.state) {
    if (!s.idea) return "something cursed"
    if (!s.ideaOwn && s.genre) return `${article(s.genre)} ${s.genre}`
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
  }

  #renderIdea(toolName) {
    const s = this.state
    const tool = this.#tool()
    const [ genreReel, phraseReel ] = this.reelTargets
    this.ideaTarget.dataset.mode = s.ownOpen ? "own" : "roll"
    this.articleTarget.textContent = s.genre ? article(s.genre) : "a"
    genreReel.textContent = s.genre || "…"
    genreReel.toggleAttribute("data-spinning", !s.stop1)
    phraseReel.textContent = s.phrase || "…"
    phraseReel.toggleAttribute("data-spinning", !s.stop2)
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
      : s.holding ? "Keep holding…"
      : "Hold to sign with Hack Club"
    this.signHintTarget.textContent = s.signing ? "Your pledge is tied to your Hack Club account."
      : !s.pace && !s.buildTime ? "Answer both to sign."
      : !s.pace ? "Pick a pace first."
      : !s.buildTime ? "Pick a time first."
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
