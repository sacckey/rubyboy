const BUFFERED_FRAMES = 2048;
const BUFFER_MASK = BUFFERED_FRAMES - 1;

class RubyboyAudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.samplesLeft = new Float32Array(BUFFERED_FRAMES);
    this.samplesRight = new Float32Array(BUFFERED_FRAMES);
    this.readCursor = 0;
    this.writeCursor = 0;
    this.phase = 0;
    this.step = 48000 / sampleRate;
    this.port.onmessage = ({ data }) => {
      if (data === 'clear') {
        this.readCursor = this.writeCursor = this.phase = 0;
        return;
      }
      const samples = new Float32Array(data);
      for (let i = 0; i + 1 < samples.length; i += 2) {
        if (this.writeCursor - this.readCursor >= BUFFERED_FRAMES - 1) this.readCursor += 1;
        const cursor = this.writeCursor & BUFFER_MASK;
        this.samplesLeft[cursor] = samples[i];
        this.samplesRight[cursor] = samples[i + 1];
        this.writeCursor += 1;
      }
    };
  }

  process(_inputs, outputs) {
    const left = outputs[0][0];
    const right = outputs[0][1];
    if (!left || !right) return true;
    for (let i = 0; i < left.length; i += 1) {
      const available = this.writeCursor - this.readCursor;
      if (available >= 2) {
        const first = this.readCursor & BUFFER_MASK;
        const second = (this.readCursor + 1) & BUFFER_MASK;
        left[i] = this.samplesLeft[first] + (this.samplesLeft[second] - this.samplesLeft[first]) * this.phase;
        right[i] = this.samplesRight[first] + (this.samplesRight[second] - this.samplesRight[first]) * this.phase;
        this.phase += this.step;
        const consumed = Math.floor(this.phase);
        this.readCursor += Math.min(consumed, available);
        this.phase -= consumed;
      } else {
        left[i] = right[i] = 0;
        this.phase = 0;
      }
    }
    return true;
  }
}

registerProcessor('rubyboy-audio-processor', RubyboyAudioProcessor);
