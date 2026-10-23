#!/usr/bin/env python3
"""Fetch the official Godot 4.6.3 Linux release template ZIP entry.

Uses HTTPS ranges, validates the existing sparse archive's directory against the
live official asset, checks entry sizes/CRC, and records SHA-256 receipts. Never
exports, executes an EXE, signs, installs, or retries through another endpoint.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import struct
import sys
sys.dont_write_bytecode = True
import urllib.parse
import urllib.request
import zipfile
import zlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "release"))
from audit_packages import AuditError, require

API = 'https://api.github.com/repos/godotengine/godot-builds/releases/tags/4.6.3-stable'
ASSET = 'Godot_v4.6.3-stable_export_templates.tpz'
URL = 'https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/' + ASSET
ENTRIES = ('linux_release.x86_64',)
HEADERS = {'User-Agent': 'PoolCore-official-template-readiness', 'Accept-Encoding': 'identity'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fetch_range(start, end, total):
    request = urllib.request.Request(URL, headers={**HEADERS, 'Range': f'bytes={start}-{end}'})
    with urllib.request.urlopen(request, timeout=90) as response:
        require(response.status == 206, 'Official asset did not honor bounded Range; no full-archive fallback')
        require(response.headers.get('Content-Range') == f'bytes {start}-{end}/{total}', 'Wrong HTTP Content-Range')
        final = urllib.parse.urlsplit(response.url)
        require(final.scheme == 'https' and final.hostname in ('github.com', 'release-assets.githubusercontent.com'),
                'Unexpected non-official release redirect')
        data = response.read(end - start + 2)
        require(len(data) == end - start + 1, 'Wrong HTTP range response length')
        return data, final.hostname


def acquire(index, output, evidence):
    index, output, evidence = Path(index), Path(output), Path(evidence)
    require(index.is_file() and not index.is_symlink(), 'Existing sparse official ZIP index required')
    require(not evidence.exists(), 'Evidence destination already exists')
    require(all(not (output / name).exists() for name in ENTRIES), 'Refusing to replace installed Linux template')
    with urllib.request.urlopen(urllib.request.Request(API, headers=HEADERS), timeout=30) as response:
        release = json.load(response)
    assets = [a for a in release['assets'] if a['name'] == ASSET]
    require(len(assets) == 1, 'Official release asset is missing or ambiguous')
    asset = assets[0]
    require(asset['browser_download_url'] == URL and asset['size'] == index.stat().st_size,
            'Official release metadata differs from existing ZIP index')
    total = asset['size']
    tail_size = min(total, 131072)
    tail, host = fetch_range(total - tail_size, total - 1, total)
    with index.open('rb') as stream:
        stream.seek(total - tail_size)
        require(stream.read() == tail, 'Official archive directory differs from the existing sparse index')
    receipt = {'format': 1, 'status': 'PASS', 'source_api': API, 'source_url': URL,
               'release_tag': release['tag_name'], 'official_asset_id': asset['id'],
               'official_archive_bytes': total, 'official_archive_digest_metadata': asset.get('digest'),
               'full_archive_digest_verified': False,
               'verification_scope': 'Only requested entries downloaded. Live archive directory matched; each local header, deflate stream, uncompressed size and ZIP CRC checked. Result SHA-256 recorded.',
               'archive_tail_sha256': sha(tail), 'archive_tail_bytes': tail_size,
               'redirect_host': host, 'downloaded_entries': [], 'windows_execution': False,
               'export_performed': False, 'retrieved_utc': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}
    # No changes to the installed template directory until ALL entries validate.
    validated = []
    with zipfile.ZipFile(index) as archive:
        for name in ENTRIES:
            entry = archive.getinfo('templates/' + name)
            require(entry.compress_type in (0, 8) and not entry.flag_bits & 1, 'Unsupported/encrypted official ZIP entry')
            header, _ = fetch_range(entry.header_offset, entry.header_offset + 29, total)
            signature, version, flags, method, tm, dt, crc, compressed, size, namesize, extrasize = struct.unpack('<I5H3I2H', header)
            require(signature == 0x04034b50 and method == entry.compress_type and not flags & 1, 'Invalid local ZIP entry header')
            require(compressed == entry.compress_size and size == entry.file_size and crc == entry.CRC,
                    'Local ZIP size/CRC differs from verified central directory')
            length = 30 + namesize + extrasize + compressed
            raw, _ = fetch_range(entry.header_offset, entry.header_offset + length - 1, total)
            require(raw[:30] == header and raw[30:30 + namesize].decode('utf-8') == entry.filename,
                    'Official entry name/header changed during retrieval')
            payload = raw[30 + namesize + extrasize:]
            if method == 8:
                decoder = zlib.decompressobj(-15)
                data = decoder.decompress(payload, size + 1)
                require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail,
                        'Invalid or oversized official deflate stream')
            else:
                data = payload
            require(len(data) == size and zlib.crc32(data) & 0xffffffff == crc, 'Official entry CRC/size mismatch')
            require(data[:4] == b'\x7fELF', 'Official Linux template lacks ELF header')
            validated.append((name, data))
            receipt['downloaded_entries'].append({'archive_path': entry.filename,
                'header_offset': entry.header_offset, 'entry_download_bytes': len(raw),
                'compressed_bytes': compressed, 'bytes': size, 'zip_crc32': f'{crc:08x}',
                'entry_sha256': sha(raw), 'sha256': sha(data)})
    output.mkdir(parents=True, exist_ok=True)
    for name, data in validated:
        with (output / name).open('xb') as stream:
            stream.write(data)
        require(sha((output / name).read_bytes()) == sha(data), 'Installed template hash changed')
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(acquire(args.index, args.output, args.evidence), indent=2))
        return 0
    except Exception as exc:
        # No mirror or alternate endpoint retries. Do not expose signed redirect URLs.
        print(f'LINUX_TEMPLATE_FETCH_FAIL: {type(exc).__name__}: {str(exc).split("?")[0]}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
