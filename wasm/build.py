#!/usr/bin/env python3
"""Compile the browser Executor with upstream Spinel and the WASI SDK."""
import argparse
import os
from pathlib import Path
import shlex
import struct
import subprocess

ROOT = Path(__file__).resolve().parent.parent
ENTRIES = ('init', 'exec', 'read_rom_from_virtual_fs', 'read_pre_installed_rom')


def run(argv, **kwargs):
    argv = [str(value) for value in argv]
    print(shlex.join(argv), flush=True)
    subprocess.run(argv, check=True, **kwargs)


def leb128(value):
    out = bytearray()
    while True:
        byte, value = value & 0x7f, value >> 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def files_section(paths):
    """A 'rubyboy-files' custom section: (path length, path, size, bytes) per file."""
    payload = bytearray()
    for path in paths:
        name, data = ('/' + path).encode(), (ROOT / path).read_bytes()
        payload += struct.pack('<I', len(name)) + name + struct.pack('<I', len(data)) + data
    body = leb128(len(b'rubyboy-files')) + b'rubyboy-files' + payload
    return b'\0' + leb128(len(body)) + body


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
    environment = dict(os.environ, WASI_SDK=str(sdk))
    entry = ROOT / 'wasm/spinel_main.rb'
    # Emit C with callable entry points instead of main(); wasm/glue.c exports them to JavaScript.
    run([compiler, '--target=wasm32-wasi', '-c', '--force', '--no-line-map',
         '--ext-init', 'Init_rubyboy_browser',
         '--ext-entry', ','.join('RubyboyBrowser.' + name for name in ENTRIES),
         entry, '-o', build / 'rubyboy.c'], env=environment, cwd=ROOT)

    # Link with the same flags and runtime that Spinel itself uses for wasm32-wasi.
    flags, libraries = [], []
    ingredients = subprocess.check_output([compiler, '--target=wasm32-wasi', '--print-build', entry],
                                          env=environment, cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
    for kind, _, value in (line.partition(' ') for line in ingredients.splitlines()):
        if kind in ('cflag', 'define'):
            flags.append(value)
        elif kind == 'include':
            flags.append('-I' + value)
        elif kind in ('runtime', 'lib'):
            libraries.append(value)
    wasm = build / 'rubyboy-spinel.wasm'
    run([clang, '-O2', '-mexec-model=reactor', '-ffunction-sections', '-fdata-sections', '-Wno-all',
         *flags, '-I' + str(build), build / 'rubyboy.c', ROOT / 'wasm/glue.c', *libraries,
         '-Wl,--gc-sections', '-Wl,--export=malloc', '-Wl,--export=free', '-o', wasm])

    # Embed only Git-tracked ROM files so local saves and states stay out of the Wasm.
    roms = [path for path in subprocess.check_output(
        ['git', '-C', ROOT, 'ls-files', '-z', 'lib/roms'], text=True).split('\0') if path]
    (output / 'rubyboy-spinel.wasm').write_bytes(wasm.read_bytes() + files_section(roms))

    html = (ROOT / 'docs/index.html').read_text()
    for asset in ('favicon.png', 'styles.css', 'index.js', 'logo-light-23.svg'):
        html = html.replace(f'"./{asset}"', f'"../{asset}"')
    html = html.replace('running on ruby.wasm', 'compiled with Spinel to WebAssembly')
    html = html.replace('<title>Ruby Boy (ruby.wasm)</title>', '<title>Ruby Boy (Spinel)</title>')
    html = html.replace('<span aria-current="page">ruby.wasm</span>\n            <a href="./spinel/">Spinel</a>',
                        '<a href="../">ruby.wasm</a>\n            <span aria-current="page">Spinel</span>')
    html = html.replace('CRuby compiled to WebAssembly', 'Ruby compiled to C, then to WebAssembly')
    html = html.replace('property="og:url" content="https://sacckey.github.io/rubyboy/"',
                        'property="og:url" content="https://sacckey.github.io/rubyboy/spinel/"')
    html = html.replace('property="og:title" content="Ruby Boy"', 'property="og:title" content="Ruby Boy (Spinel)"')
    (output / 'index.html').write_text(html)
    size = (output / 'rubyboy-spinel.wasm').stat().st_size
    print(f"Built {output / 'rubyboy-spinel.wasm'}: {size:,} bytes")


if __name__ == '__main__':
    main()
