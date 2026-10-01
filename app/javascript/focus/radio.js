// Wrong Tool Radio: lo-fi made on the spot with Web Audio, for focus sessions. Each track is a tempo and four
// chords; every bar gets pads, bass, a kick and snare, swung hats and the odd sparkle, over a little vinyl crackle.
// It calls `onBeat` on every beat so things can move to it.

export const TRACKS = [
  { name: "#REF! in the rain", tag: "A1", color: "#ec3750", bpm: 76, chords: [ [ 57, 60, 64, 67 ], [ 53, 57, 60, 64 ], [ 55, 59, 62, 65 ], [ 52, 55, 59, 62 ] ] },
  { name: "Merge conflict lullaby", tag: "B2", color: "#1a73e8", bpm: 84, chords: [ [ 50, 53, 57, 60 ], [ 55, 59, 62, 65 ], [ 48, 52, 55, 59 ], [ 57, 60, 64, 67 ] ] },
  { name: "Ctrl+Z forever", tag: "C3", color: "#1e7b45", bpm: 70, chords: [ [ 53, 57, 60, 64 ], [ 52, 55, 59, 62 ], [ 50, 53, 57, 60 ], [ 55, 59, 62, 65 ] ] }
]

const frequency = (note) => 440 * Math.pow(2, (note - 69) / 12)

export class Radio {
  constructor(onBeat) {
    this.onBeat = onBeat
    const audio = this.audio = new (window.AudioContext || window.webkitAudioContext)()
    this.out = audio.createGain()
    this.out.gain.value = 0.55
    const lowpass = audio.createBiquadFilter()
    lowpass.type = "lowpass"
    lowpass.frequency.value = 5200
    this.analyser = audio.createAnalyser()
    this.analyser.fftSize = 128
    this.analyser.smoothingTimeConstant = 0.78
    this.out.connect(lowpass)
    lowpass.connect(this.analyser)
    this.analyser.connect(audio.destination)

    this.noise = this.#buffer(() => Math.random() * 2 - 1)
    const crackle = audio.createBufferSource()
    crackle.buffer = this.#buffer(() => (Math.random() < 0.0006 ? 0.7 : 0.01) * (Math.random() * 2 - 1))
    crackle.loop = true
    crackle.connect(this.out)
    crackle.start()

    this.track = 0
    this.step = 0
    this.next = audio.currentTime + 0.1
    this.timer = setInterval(() => this.#schedule(), 25)
  }

  get playing() {
    return this.audio.state === "running"
  }

  play() { return this.audio.resume() }
  pause() { return this.audio.suspend() }

  setTrack(index) {
    this.track = index
    this.step = 0
    this.next = this.audio.currentTime + 0.1
  }

  // Three rising notes, for a round done.
  chime() {
    const now = this.audio.currentTime;
    [ 76, 79, 84 ].forEach((note, index) => this.#tone("sine", frequency(note), now + index * 0.14, 0.01, 0.16, 1.4))
  }

  // How loud each band is right now, 0 to 1, for an equalizer.
  levels(count) {
    const data = new Uint8Array(this.analyser.frequencyBinCount)
    if (this.playing) this.analyser.getByteFrequencyData(data)
    return Array.from({ length: count }, (_, index) => data[1 + index * 2] / 255)
  }

  close() {
    this.onBeat = null
    clearInterval(this.timer)
    this.audio.close()
  }

  #buffer(sample) {
    const length = this.audio.sampleRate * 2
    const buffer = this.audio.createBuffer(1, length, this.audio.sampleRate)
    const data = buffer.getChannelData(0)
    for (let index = 0; index < length; index++) data[index] = sample()
    return buffer
  }

  // Queues up whatever falls in the next 120ms, a sixteenth at a time.
  #schedule() {
    if (!this.playing) return
    const track = TRACKS[this.track]
    const sixteenth = 60 / track.bpm / 4
    while (this.next < this.audio.currentTime + 0.12) {
      this.#play(this.step, this.next, track, sixteenth)
      this.next += sixteenth
      this.step = (this.step + 1) % 64
    }
  }

  #play(step, start, track, sixteenth) {
    const time = start + (step % 2 ? sixteenth * 0.28 : 0) // swing
    const beat = step % 16
    const chord = track.chords[Math.floor(step / 16)]
    if (beat === 0) chord.forEach((note, index) => this.#tone("triangle", frequency(note), time + index * 0.012, 0.25, 0.045, sixteenth * 15, index % 2 ? 7 : -7))
    if (beat === 0 || beat === 10) this.#tone("sine", frequency(chord[0] - 24), time, 0.01, 0.32, sixteenth * 5)
    if (beat === 0 || beat === 7 || beat === 10) {
      const kick = this.#tone("sine", 110, time, 0.003, 0.75, 0.3)
      kick.frequency.exponentialRampToValueAtTime(42, time + 0.12)
    }
    if (beat === 4 || beat === 12) this.#hit(time, 1400, 0.2, 0.16)
    if (beat % 2 === 0) this.#hit(time, 7000, beat % 4 === 2 ? 0.06 : 0.03, 0.04)
    if (beat % 3 === 1 && Math.random() < 0.45) this.#tone("sine", frequency(chord[Math.floor(Math.random() * 4)] + 12), time, 0.005, 0.08, 0.5)
    if (beat % 4 === 0) setTimeout(() => this.onBeat?.(), Math.max(0, (time - this.audio.currentTime) * 1000))
  }

  #envelope(node, time, attack, peak, decay) {
    const gain = this.audio.createGain()
    gain.gain.setValueAtTime(0.0001, time)
    gain.gain.exponentialRampToValueAtTime(peak, time + attack)
    gain.gain.exponentialRampToValueAtTime(0.0001, time + attack + decay)
    node.connect(gain)
    gain.connect(this.out)
  }

  #tone(type, hertz, time, attack, peak, decay, detune = 0) {
    const oscillator = this.audio.createOscillator()
    oscillator.type = type
    oscillator.frequency.setValueAtTime(hertz, time)
    oscillator.detune.value = detune
    this.#envelope(oscillator, time, attack, peak, decay)
    oscillator.start(time)
    oscillator.stop(time + attack + decay + 0.05)
    return oscillator
  }

  #hit(time, highpass, peak, decay) {
    const source = this.audio.createBufferSource()
    source.buffer = this.noise
    const filter = this.audio.createBiquadFilter()
    filter.type = "highpass"
    filter.frequency.value = highpass
    source.connect(filter)
    this.#envelope(filter, time, 0.002, peak, decay)
    source.start(time, Math.random() * 1.5)
    source.stop(time + decay + 0.05)
  }
}
