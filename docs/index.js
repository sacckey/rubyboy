const worker = new Worker('worker.js', { type: 'module' });
const playbackOptions = new URLSearchParams(window.location.search);
const throttleToggle = document.getElementById('throttle-toggle');
const muteToggle = document.getElementById('mute-toggle');
throttleToggle.checked = playbackOptions.get('throttle') !== '0';
muteToggle.checked = playbackOptions.get('mute') !== '0';

class AudioPlayer {
  constructor() {
    this.context = null;
    this.processor = null;
    this.startingPromise = null;
    this.muted = muteToggle.checked;
  }

  async ensureStarted() {
    if (this.muted) return;
    if (!this.context) {
      try {
        this.context = new window.AudioContext({ sampleRate: 48000, latencyHint: 'interactive' });
      } catch (_) {
        this.context = new window.AudioContext({ latencyHint: 'interactive' });
      }
    }
    // Resume from the first gesture before waiting for the worklet download.
    const resume = this.context.resume();
    if (!this.processor && !this.startingPromise) {
      this.startingPromise = this.context.audioWorklet.addModule('./audio-worklet.js').then(() => {
        this.processor = new AudioWorkletNode(this.context, 'rubyboy-audio-processor', {
          numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [2],
        });
        this.processor.connect(this.context.destination);
      }).finally(() => { this.startingPromise = null; });
    }
    await Promise.all([resume, this.startingPromise]);
    if (this.muted) {
      this.clear();
      await this.context.suspend();
    }
  }

  async setMuted(enabled) {
    this.muted = Boolean(enabled);
    this.clear();
    if (this.muted) {
      if (this.context) await this.context.suspend();
    } else {
      await this.ensureStarted();
    }
  }

  clear() { this.processor?.port.postMessage('clear'); }

  enqueue(buffer) {
    if (!this.muted && this.processor && this.context.state === 'running') {
      this.processor.port.postMessage(buffer, [buffer]);
    }
  }
}

const audioPlayer = new AudioPlayer();
function startAudio() {
  audioPlayer.ensureStarted().catch((error) => console.error('Audio initialization failed:', error));
}
document.addEventListener('pointerdown', startAudio);
document.addEventListener('keydown', startAudio);
throttleToggle.addEventListener('change', () => {
  worker.postMessage({ type: 'setThrottle', enabled: throttleToggle.checked });
});
muteToggle.addEventListener('change', () => {
  audioPlayer.setMuted(muteToggle.checked).catch((error) => console.error('Audio initialization failed:', error));
  worker.postMessage({ type: 'setMute', enabled: muteToggle.checked });
});

const SCALE = 2;
const canvas = document.getElementById('canvas');
const canvasContext = canvas.getContext('2d');
canvasContext.scale(SCALE, SCALE);
const tmpCanvas = document.createElement('canvas');
const tmpCanvasContext = tmpCanvas.getContext('2d');
tmpCanvas.width = canvas.width;
tmpCanvas.height = canvas.height;

// Display "LOADING..."
(() => {
  const str = `
    10000 01110 01110 11110 01110 10001 01110 00000 00000 00000
    10000 10001 10001 10001 00100 11001 10000 00000 00000 00000
    10000 10001 10001 10001 00100 10101 10011 00000 00000 00000
    10000 10001 11111 10001 00100 10011 10001 01100 01100 01100
    11111 01110 10001 11110 01110 10001 01110 01100 01100 01100
  `;
  const dotSize = 2;
  const rows = str.trim().split('\n')
  const xSpacing = canvas.width / (2 * SCALE) - rows[0].length * dotSize / 2;
  const ySpacing = canvas.height / (2 * SCALE) - rows.length * dotSize / 2;
  canvasContext.fillStyle = 'white';

  rows.forEach((row, y) => {
    [...row.trim()].forEach((char, x) => {
      if (char === '1') {
        canvasContext.fillRect(
          x * dotSize + xSpacing,
          y * dotSize + ySpacing,
          dotSize,
          dotSize
        );
      }
    });
  });
})();

const inputBindings = {
  KeyD: ['direction', 1], KeyA: ['direction', 2], KeyW: ['direction', 4], KeyS: ['direction', 8],
  KeyK: ['action', 1], KeyJ: ['action', 2], KeyU: ['action', 4], KeyI: ['action', 8],
};
const pressedSources = new Map();
function sendInput() {
  const masks = { direction: 0, action: 0 };
  for (const code of pressedSources.values()) {
    const binding = inputBindings[code];
    if (binding) masks[binding[0]] |= binding[1];
  }
  worker.postMessage({ type: 'input', ...masks });
}
function releaseInputs() {
  pressedSources.clear();
  sendInput();
  worker.postMessage({ type: 'releaseInputs' });
}
for (const type of ['keydown', 'keyup']) {
  document.addEventListener(type, (event) => {
    if (!inputBindings[event.code]) return;
    const typing = event.target.isContentEditable || ['SELECT', 'TEXTAREA'].includes(event.target.tagName)
      || (event.target.tagName === 'INPUT' && !['checkbox', 'radio', 'button'].includes(event.target.type));
    if (type === 'keydown' && typing) return;
    event.preventDefault();
    if (type === 'keydown') pressedSources.set(`key:${event.code}`, event.code);
    else pressedSources.delete(`key:${event.code}`);
    sendInput();
  });
}
window.addEventListener('blur', releaseInputs);
document.addEventListener('visibilitychange', () => { if (document.hidden) releaseInputs(); });
const buttons = document.querySelectorAll('.d-pad-button, .action-button, .start-select-button');
buttons.forEach(button => {
  button.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    pressedSources.set(`pointer:${event.pointerId}`, button.dataset.code);
    sendInput();
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    button.addEventListener(type, (event) => {
      pressedSources.delete(`pointer:${event.pointerId}`);
      sendInput();
    });
  }
  button.addEventListener('click', (event) => {
    if (event.detail !== 0) return;
    startAudio();
    const source = `activate:${button.dataset.code}`;
    pressedSources.set(source, button.dataset.code);
    sendInput();
    pressedSources.delete(source);
    sendInput();
  });
});

const romInput = document.getElementById('rom-input');
let romRequest = 0;
romInput.addEventListener('change', (event) => {
  const file = event.target.files[0];
  if (file) {
    const request = ++romRequest;
    const reader = new FileReader();

    reader.onload = (e) => {
      if (request !== romRequest) return;
      const romData = e.target.result;
      releaseInputs();
      audioPlayer.clear();
      worker.postMessage({ type: 'loadROM', data: romData }, [romData]);
    };

    reader.readAsArrayBuffer(file);
  }
});

const romSelectBox = document.getElementById('rom-select-box');
romSelectBox.addEventListener('change', (event) => {
  romRequest += 1;
  releaseInputs();
  audioPlayer.clear();
  worker.postMessage({ type: 'loadPreInstalledRom', romName: event.target.value });
});

const times = [];
const fpsDisplay = document.getElementById('fps-display');
worker.onmessage = (event) => {
  if (event.data.type === 'audioData') {
    audioPlayer.enqueue(event.data.data);
  }

  if (event.data.type === 'romLoaded') {
    times.length = 0;
    audioPlayer.clear();
  }

  if (event.data.type === 'pixelData') {
    const pixelData = new Uint8ClampedArray(event.data.data);
    const imageData = new ImageData(pixelData, 160, 144);
    tmpCanvasContext.putImageData(imageData, 0, 0);
    canvasContext.drawImage(tmpCanvas, 0, 0);

    const now = performance.now();
    while (times.length > 0 && times[0] <= now - 1000) {
      times.shift();
    }
    times.push(now);
    fpsDisplay.innerText = times.length.toString();
  }

  if (event.data.type === 'initialized') {
    romSelectBox.disabled = false;
    romInput.disabled = false;
    document.getElementById('rom-upload-button').classList.remove('disabled');
    worker.postMessage({ type: 'setThrottle', enabled: throttleToggle.checked });
    worker.postMessage({ type: 'setMute', enabled: muteToggle.checked });
    worker.postMessage({ type: 'startRubyboy' });
  }

  if (event.data.type === 'error') {
    console.error('Error from Worker:', event.data.message);
  }
};

worker.postMessage({ type: 'initRubyboy' });
