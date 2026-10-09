#!/usr/bin/env python3
"""Compile the existing Ruby browser executor using Spinel's generic Wasm host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ENTRIES = ('init', 'exec', 'read_rom_from_virtual_fs', 'read_pre_installed_rom')


def run(argv, **kwargs):
    argv = [str(value) for value in argv]
    print(shlex.join(argv), flush=True)
    subprocess.run(argv, check=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spinel-dir', type=Path,
                        default=Path(os.environ.get('SPINEL_DIR', ROOT.parent / 'spinel')))
    parser.add_argument('--wasi-sdk', type=Path,
                        default=Path(os.environ.get('WASI_SDK', os.environ.get('WASI_SDK_PATH', '/opt/wasi-sdk'))))
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'docs/spinel')
    args = parser.parse_args()
    spinel, sdk, output = args.spinel_dir.resolve(), args.wasi_sdk.resolve(), args.output_dir.resolve()
    compiler, clang = spinel / 'bin/spinel', sdk / 'bin/clang'
    if not clang.is_file() or not (spinel / 'Makefile').is_file():
        parser.error('pass --spinel-dir and --wasi-sdk pointing to Spinel and WASI SDK 34+')
    build = ROOT / 'build/spinel-wasm'
    build.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    run(['make', '-C', spinel, '-j4', 'bin/spinel'])
    run(['make', '-C', spinel, '-j4', '-B', 'wasm-rt', 'WASI_SDK=' + str(sdk), 'COPT=-O2'])
    environment = os.environ.copy()
    environment['WASI_SDK'] = str(sdk)
    run([compiler, '-O2', '--target=wasm32-wasi', '--cc=' + str(clang), '--no-line-map',
         '--ext', 'wasm', '--ext-init', 'Init_rubyboy_browser', '--ext-entry',
         ','.join('RubyboyBrowser.' + name for name in ENTRIES),
         ROOT / 'wasm/spinel_main.rb', '-o', build / 'rubyboy-spinel.wasm'], env=environment, cwd=ROOT)
    # Embed only Git-tracked ROM files so local saves and states stay out of the Wasm.
    roms = [ROOT / path for path in subprocess.check_output(
        ['git', '-C', ROOT, 'ls-files', '-z', 'lib/roms'], text=True).split('\0') if path]
    with tempfile.TemporaryDirectory() as staging:
        for rom in roms:
            target = Path(staging) / rom.relative_to(ROOT / 'lib/roms')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(rom, target)
        run(['python3', spinel / 'scripts/wasm-pack.py', build / 'rubyboy-spinel.wasm',
             '--dir', staging + '::/lib/roms', '-o', output / 'rubyboy-spinel.wasm'])
    # Distribute the generic host without keeping a separately maintained copy.
    host = spinel / 'lib/wasm/spinel-vm.mjs'
    shutil.copyfile(host, output / 'spinel-vm.mjs')
    html = (ROOT / 'docs/index.html').read_text()
    for asset in ('favicon.png', 'styles.css', 'index.js', 'logo-light-23.svg'):
        html = html.replace(f'"./{asset}"', f'"../{asset}"')
    html = html.replace('running on ruby.wasm', 'compiled with Spinel to WebAssembly')
    html = html.replace('property="og:url" content="https://sacckey.github.io/rubyboy/"',
                        'property="og:url" content="https://sacckey.github.io/rubyboy/spinel/"')
    (output / 'index.html').write_text(html)
    metadata = {
        'pipeline': 'Existing Ruby Executor -> Spinel generated C and Wasm host -> WebAssembly',
        'spinel': subprocess.check_output([compiler, '--version'], text=True).strip(),
        'clang': subprocess.check_output([clang, '--version'], text=True).splitlines()[0],
        'rubyboy_revision': subprocess.check_output(['git', '-C', ROOT, 'rev-parse', 'HEAD'], text=True).strip(),
        'spinel_revision': subprocess.check_output(['git', '-C', spinel, 'rev-parse', 'HEAD'], text=True).strip(),
        'rubyboy_diff_sha256': hashlib.sha256(subprocess.check_output(['git', '-C', ROOT, 'diff', 'HEAD'])).hexdigest(),
        'spinel_diff_sha256': hashlib.sha256(subprocess.check_output(['git', '-C', spinel, 'diff', 'HEAD'])).hexdigest(),
        'executor_sha256': digest(ROOT / 'lib/executor.rb'),
        'emulator_sha256': digest(ROOT / 'lib/rubyboy/emulator_wasm.rb'),
        'host_sha256': digest(host),
        'packer_sha256': digest(spinel / 'scripts/wasm-pack.py'),
        'entry_sha256': digest(ROOT / 'wasm/spinel_main.rb'),
        'roms': [{'path': '/lib/roms/' + path.relative_to(ROOT / 'lib/roms').as_posix(),
                  'bytes': path.stat().st_size, 'sha256': digest(path)}
                 for path in roms],
        'wasm_bytes': (output / 'rubyboy-spinel.wasm').stat().st_size,
        'wasm_sha256': digest(output / 'rubyboy-spinel.wasm'),
    }
    (output / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f"Built {output / 'rubyboy-spinel.wasm'}: {metadata['wasm_bytes']:,} bytes")


if __name__ == '__main__':
    main()
