const worker = new Worker('worker.js', { type: 'module' });

const canvas = document.getElementById('canvas');
const canvasContext = canvas.getContext('2d');
canvasContext.scale(2, 2);
const tmpCanvas = document.createElement('canvas');
const tmpCanvasContext = tmpCanvas.getContext('2d');
tmpCanvas.width = canvas.width;
tmpCanvas.height = canvas.height;

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

worker.onmessage = (event) => {
  if (event.data.type === 'pixelData') {
    const pixelData = new Uint8ClampedArray(event.data.data);
    const imageData = new ImageData(pixelData, 160, 144);
    tmpCanvasContext.putImageData(imageData, 0, 0);
    canvasContext.drawImage(tmpCanvas, 0, 0);
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
