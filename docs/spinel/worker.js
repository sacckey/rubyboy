import * as shim from 'https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.4.2/+esm';
import { createSpinelVM } from './spinel-vm.mjs';
import { RubyboyVM } from '../rubyboy-vm.js';
import { startEmulationWorker } from '../emulation-worker.js';

startEmulationWorker(async () => {
  const response = await fetch(new URL('./rubyboy.wasm', import.meta.url));
  if (!response.ok) throw new Error(`Wasm download failed (${response.status}). Build wasm/build.py first.`);
  const module = await WebAssembly.compile(await response.arrayBuffer());
  const { vm, root } = await createSpinelVM(module, { shim });
  vm.call('RubyboyBrowser.init', '/lib/roms/tobu.gb');
  const executor = { call: (method, ...args) => vm.call(`RubyboyBrowser.${method}`, ...args) };
  return {
    adapter: new RubyboyVM(vm, root, shim.File, { executor, toValue: value => value }),
    runtime: { backend: 'spinel' },
  };
});
