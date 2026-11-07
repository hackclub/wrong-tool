import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"

// Your project page. Clippy hops for each step you tick off, and congratulates you once setup's done.
export default class extends Controller {
  static targets = [ "clippy", "sprite" ]
  static values = { clippy: String, mood: String, sounds: Object }

  connect() {
    if (!this.hasSpriteTarget) return

    this.clippy = new Clippy(this.spriteTarget, this.soundsValue)
    this.clippy.feel(this.moodValue || "idle", { first: this.clippyValue === "congratulate" ? "Congratulate" : null })
    if (this.clippyValue) this.#hop()
  }

  disconnect() {
    this.clippy?.stop()
    clearTimeout(this.hopTimer)
  }

  #hop() {
    this.clippyTarget.toggleAttribute("data-hop", true)
    this.hopTimer = setTimeout(() => this.clippyTarget.toggleAttribute("data-hop", false), 180)
  }
}
