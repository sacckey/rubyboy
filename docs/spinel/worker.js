import * as shim from 'https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.4.2/+esm';
import { createRubyboySpinel } from './rubyboy-spinel.mjs';
import { RubyboyVM } from '../rubyboy-vm.js';
import { startEmulationWorker } from '../emulation-worker.js';

startEmulationWorker(async () => {
  let response = await fetch(new URL('./rubyboy-spinel.wasm', import.meta.url));
  if (!response.ok) response = await fetch('https://proxy.sacckey.dev/rubyboy-spinel.wasm');
  if (!response.ok) throw new Error(`Wasm download failed (${response.status}).`);
  const module = await WebAssembly.compile(await response.arrayBuffer());
  const { root, executor } = await createRubyboySpinel(module, shim);
  return new RubyboyVM(null, root, shim.File, { executor, toValue: value => value });
});
