import { Controller } from "@hotwired/stimulus"
import { Clippy } from "mascot/clippy"

// Your project page. Setting up opens where each step happens (Hackatime, Slack) in a new tab while the
// form ticks it off here; Clippy hops for each step and congratulates you once setup's done.
export default class extends Controller {
  static targets = [ "clippy", "sprite" ]
  static values = { clippy: String, sounds: Object }

  connect() {
    this.clippy = new Clippy(this.spriteTarget, this.soundsValue)
    if (this.clippyValue === "congratulate") this.clippy.congratulate()
    if (this.clippyValue) this.#hop()
  }

  disconnect() {
    this.clippy.stop()
    clearTimeout(this.hopTimer)
  }

  // A step's button carries where it happens (data-url); that opens alongside the form's submission.
  open({ submitter }) {
    const url = submitter?.dataset.url
    if (url) window.open(url, "_blank", "noopener")
  }

  #hop() {
    this.clippyTarget.toggleAttribute("data-hop", true)
    this.hopTimer = setTimeout(() => this.clippyTarget.toggleAttribute("data-hop", false), 180)
  }
}
