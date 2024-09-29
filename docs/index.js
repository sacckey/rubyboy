const worker = new Worker('worker.js', { type: 'module' });

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

document.addEventListener('keydown', (event) => {
  worker.postMessage({ type: 'keydown', code: event.code });
});
document.addEventListener('keyup', (event) => {
  worker.postMessage({ type: 'keyup', code: event.code });
});

const handleButtonPress = (event) => {
  event.preventDefault();
  worker.postMessage({ type: 'keydown', code: event.target.dataset.code });
}
const handleButtonRelease = (event) => {
  event.preventDefault();
  worker.postMessage({ type: 'keyup', code: event.target.dataset.code });
}
const buttons = document.querySelectorAll('.d-pad-button, .action-button, .start-select-button');
buttons.forEach(button => {
  button.addEventListener('mousedown', handleButtonPress);
  button.addEventListener('mouseup', handleButtonRelease);
  button.addEventListener('touchstart', handleButtonPress);
  button.addEventListener('touchend', handleButtonRelease);
});

const romInput = document.getElementById('rom-input');
romInput.addEventListener('change', (event) => {
  const file = event.target.files[0];
  if (file) {
    const reader = new FileReader();

    reader.onload = (e) => {
      const romData = e.target.result;
      worker.postMessage({ type: 'loadROM', data: romData }, [romData]);
    };

    reader.readAsArrayBuffer(file);
  }
});

const romSelectBox = document.getElementById('rom-select-box');
romSelectBox.addEventListener('change', (event) => {
  worker.postMessage({ type: 'loadPreInstalledRom', romName: event.target.value });
});

const times = [];
const fpsDisplay = document.getElementById('fps-display');
worker.onmessage = (event) => {
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
    worker.postMessage({ type: 'startRubyboy' });
  }

  if (event.data.type === 'error') {
    console.error('Error from Worker:', event.data.message);
  }
};

worker.postMessage({ type: 'initRubyboy' });
