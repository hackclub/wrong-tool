import { Controller } from "@hotwired/stimulus"

// The ship form: says what it still needs (and keeps Ship it greyed out until then), counts the description up to
// its minimum, shows the screenshot you picked, and the title as it'll read in the Hall of Wrong.
export default class extends Controller {
  static targets = [ "title", "description", "count", "repo", "demo", "file", "preview", "placeholder", "confirm",
                     "missing", "submit", "previewTitle" ]
  static values = { descriptionMin: Number, hasScreenshot: Boolean }

  connect() {
    this.check()
  }

  check() {
    const length = this.descriptionTarget.value.trim().length
    const short = length < this.descriptionMinValue
    this.countTarget.textContent = short ? `${length} / ${this.descriptionMinValue} min` : `${length} characters`
    this.countTarget.toggleAttribute("data-enough", !short)
    this.previewTitleTarget.textContent = this.titleTarget.value.trim() || "Untitled"

    const missing = [
      !this.titleTarget.value.trim() && "a title",
      short && `a description (${this.descriptionMinValue}+ characters)`,
      !this.repoTarget.value.trim() && "a repo URL",
      !this.demoTarget.value.trim() && "a demo URL",
      !this.hasScreenshotValue && !this.fileTarget.files.length && "a screenshot",
      !this.confirmTarget.checked && "a screenshot check"
    ].filter(Boolean)

    this.missingTarget.textContent = missing.length ? `Still needs ${missing.join(", ")}.` : "Ready to ship."
    this.missingTarget.toggleAttribute("data-ready", !missing.length)
    this.submitTarget.disabled = missing.length > 0
  }

  preview() {
    const [ file ] = this.fileTarget.files
    if (!file) return
    URL.revokeObjectURL(this.previewTarget.src)
    this.previewTarget.src = URL.createObjectURL(file)
    this.previewTarget.hidden = false
    this.placeholderTarget.hidden = true
  }
}
