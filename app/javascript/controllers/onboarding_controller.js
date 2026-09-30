import { Controller } from "@hotwired/stimulus"

// The onboarding sheet: pick a wrong tool (A1), roll or write an idea (A2), pick a handheld (A3) and save it
// all (A4). Tapping an answer moves on after a short flash; answered rows fold into cells that reopen them.
// Answers live in this tab (sessionStorage keeps them across the trip to Hack Club Auth) until sign-in.
const PICK_DELAY = 360
// The mascot's congratulations: [frame in the sprite strip, how long it shows (ms), sound to start]. It bends
// into a tick, holds it, waves it and straightens back up, with Clippy's own sounds on the frames it had them.
const MASCOT_FRAMES = [
  [ 0, 100, "first" ], [ 1, 10 ], [ 2, 10 ], [ 3, 10, "second" ], [ 4, 10 ], [ 5, 10 ], [ 6, 10 ], [ 7, 10 ], [ 8, 10 ], [ 9, 100 ],
  [ 10, 100 ], [ 11, 100 ], [ 12, 600 ], [ 13, 100 ], [ 14, 100 ], [ 12, 600 ],
  [ 15, 100 ], [ 16, 100 ], [ 17, 100 ], [ 18, 100 ], [ 19, 100 ], [ 0, 100 ]
]
const MASCOT_SLIDE = 280
const ANSWERS_KEY = "wrong-tool:onboarding"
const ANSWERS = [ "step", "tool", "custom", "genre", "phrase", "idea", "ideaTool", "ideaOwn", "ideaSkipped", "prize" ]

export default class extends Controller {
  static targets = [
    "row", "summary", "value",
    "tool", "otherName", "otherInput",
    "idea", "reel", "article", "dice", "rollLabel", "useIdea", "ownInput", "useOwn",
    "prize", "mascot", "mascotSprite", "mascotSay",
    "save", "receiptPhoto", "receiptTool", "receiptIdea", "receiptPrize", "signIn", "signInLabel", "gameTitle",
    "fileName", "progress", "nameBox", "formula", "projectTab"
  ]
  static values = { tools: Array, genres: Array, prizes: Array, hours: Number, sounds: Object, signedIn: Boolean }

  connect() {
    this.state = {
      step: 1, tool: null, custom: "", otherOpen: false,
      genre: "", phrase: "", idea: "", ideaTool: null, ideaOwn: false, ideaSkipped: false,
      rolling: false, stop1: true, stop2: true, spin: 0, ownOpen: false, own: "",
      prize: null, signing: false, signed: this.signedInValue,
      ...this.#restoreAnswers()
    }
    // Back from signing in with everything answered: straight to the last step.
    if (this.state.signed && this.state.prize) this.state.step = 4
    this.sounds = Object.fromEntries(Object.entries(this.soundsValue).map(([ name, url ]) => {
      const audio = new Audio(url)
      audio.preload = "auto"
      return [ name, audio ]
    }))
    this.#render()
  }

  disconnect() {
    clearTimeout(this.pickTimer)
    clearTimeout(this.rollTimer)
    clearTimeout(this.mascotTimer)
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
    this.#congratulate(this.prizesValue.find(({ id }) => id === prize).name)
    this.#goTo(4)
  }

  // A4

  // Back (from Hack Club Auth, say) to a page the browser kept as it was: the button is ready to try again.
  resume({ persisted }) {
    if (persisted && this.state.signing) this.#set({ signing: false })
  }

  // The form posts to Hack Club Auth; the answers so far wait in this tab for the trip back.
  signIn(event) {
    if (this.state.signing || this.state.signed) return event.preventDefault()
    this.#saveAnswers()
    this.#set({ signing: true })
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

  // The mascot lives over the whole sheet, so it keeps congratulating you on A4 while you carry on. Picking
  // again starts it over.
  #congratulate(prizeName) {
    clearTimeout(this.mascotTimer)
    this.mascotSayTarget.textContent = `Nice pick! The ${prizeName} is yours after ${this.hoursValue} hours.`
    this.mascotTarget.toggleAttribute("data-visible", true)

    if (reducedMotion()) {
      this.#showMascotFrame(12)
      this.#play("second")
      this.mascotTimer = setTimeout(() => this.#dismissMascot(), 1500)
    } else {
      this.#showMascotFrame(0)
      this.mascotTimer = setTimeout(() => this.#playMascot(0), MASCOT_SLIDE)
    }
  }

  #playMascot(index) {
    if (index === MASCOT_FRAMES.length) return this.#dismissMascot()
    const [ frame, duration, sound ] = MASCOT_FRAMES[index]
    this.#showMascotFrame(frame)
    if (sound) this.#play(sound)
    this.mascotTimer = setTimeout(() => this.#playMascot(index + 1), duration)
  }

  #dismissMascot() {
    this.mascotTarget.toggleAttribute("data-visible", false)
    this.mascotTimer = setTimeout(() => {
      this.mascotSayTarget.textContent = ""
      this.#showMascotFrame(0)
    }, MASCOT_SLIDE)
  }

  // From the start each time; a browser that won't play it just stays quiet.
  #play(name) {
    const audio = this.sounds[name]
    if (!audio) return
    audio.currentTime = 0
    audio.play().catch(() => {})
  }

  #showMascotFrame(frame) {
    this.mascotSpriteTarget.style.setProperty("--frame", frame)
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
    const done = { 1: !!s.tool, 2: !!s.idea || s.ideaSkipped, 3: !!prize, 4: s.signed }
    const values = {
      1: toolName,
      2: s.idea ? capitalize(s.idea) : s.ideaSkipped ? "Not decided yet" : "",
      3: prize?.full ?? "",
      4: s.signed ? "Saved to Hack Club" : ""
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
    this.#renderSave(toolName, prize)

    const slug = s.idea ? s.idea.replace(/^(a|an) /i, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 36) : "untitled_game"
    this.fileNameTarget.textContent = tool ? slug + tool.extension : "untitled_wrong_game"
    this.progressTarget.textContent = s.signed ? "A1:A4 done" : `Step ${s.step} of 4`
    this.nameBoxTarget.textContent = `A${s.step}`
    this.formulaTarget.textContent = this.#formula(toolName)
    this.element.toggleAttribute("data-saved", s.signed)
    this.projectTabTarget.setAttribute("aria-disabled", !s.signed)
  }

  #formula(toolName) {
    const s = this.state
    switch (s.step) {
      case 1: return s.otherOpen ? `=PICK("${s.custom || "…"}")` : s.tool ? `=PICK("${toolName}")` : "=PICK(platform)"
      case 2:
        if (s.rolling) return `=IDEA(RAND(), "${toolName}")`
        if (s.ownOpen) return `="${s.own}"`
        return s.idea ? `="${s.idea}"` : `=IDEA(RAND(), "${toolName}")`
      case 3: return `=PRIZE(${this.hoursValue} hrs)`
      default: return s.signed ? "=SAVE(A1:A3) → TRUE" : s.signing ? "=SAVE(A1:A3) → #LOADING" : "=SAVE(A1:A3)"
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

  #renderSave(toolName, prize) {
    const s = this.state
    this.receiptPhotoTargets.forEach(photo => { photo.hidden = photo.dataset.prize !== s.prize })
    this.receiptToolTarget.textContent = toolName || "—"
    this.receiptIdeaTarget.textContent = s.idea || "#LATER"
    this.receiptIdeaTarget.classList.toggle("onboarding-receipt__later", !s.idea)
    this.receiptPrizeTarget.textContent = prize?.full ?? "—"
    this.saveTarget.dataset.signed = s.signed
    this.signInTarget.toggleAttribute("data-signing", s.signing)
    this.signInTarget.setAttribute("aria-busy", s.signing)
    this.signInLabelTarget.textContent = s.signing ? "Signing in…" : "Get started"
    this.gameTitleTarget.textContent = s.idea ? `${capitalize(s.idea)}.` : "Your game."
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

function reducedMotion() {
  return matchMedia("(prefers-reduced-motion: reduce)").matches
}
