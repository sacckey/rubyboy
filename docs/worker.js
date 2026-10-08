import { DefaultRubyVM } from 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.10.1/dist/browser/+esm';
import { File } from 'https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.4.2/+esm';
import { startEmulationWorker } from './emulation-worker.js';
import { RubyboyVM } from './rubyboy-vm.js';

startEmulationWorker(async () => {
  // Keep the existing local-first download and proxy fallback.
  let response = await fetch('./rubyboy.wasm');
  if (!response.ok) response = await fetch('https://proxy.sacckey.dev/rubyboy.wasm');
  if (!response.ok) throw new Error(`Wasm download failed (${response.status}).`);
  const module = await WebAssembly.compileStreaming(response);
  const { vm, wasi } = await DefaultRubyVM(module);
  return {
    adapter: new RubyboyVM(vm, wasi.fds[3].dir, File),
    runtime: { ruby: vm.eval('RUBY_DESCRIPTION').toString() },
  };
});
