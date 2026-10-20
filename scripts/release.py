#!/usr/bin/env python3
"""Build a verified WoW addon ZIP; optionally upload it to CurseForge."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import urllib.error
import urllib.request
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED = {'.git', '.github', 'scripts', 'dist', 'docs', 'tests', '__pycache__', '.venv', 'node_modules'}
EXTENSIONS = {'.lua', '.xml', '.toc', '.tga', '.blp', '.png', '.jpg', '.jpeg', '.ogg', '.mp3', '.wav', '.ttf', '.otf', '.txt'}

def validate_references(files, toc):
    paths = set(files)
    def check(base, reference):
        normalized = reference.replace('\\', '/')
        if normalized.startswith(('/', 'Interface/')) or ':' in normalized:
            if normalized.startswith('Interface/'):
                return
            raise ValueError('Unsafe file reference: ' + reference)
        target = PurePosixPath(base) / normalized
        if '..' in target.parts or str(target) not in paths:
            raise ValueError('Missing or case-mismatched addon file: ' + str(target))
    for line in toc.splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            check('', line)
    for name, source in files.items():
        if name.lower().endswith('.xml'):
            text = source.read_text(encoding='utf-8-sig')
            for reference in re.findall(r'<(?:Script|Include)\b[^>]*\bfile\s*=\s*[\"\x27]([^\"\x27]+)', text, re.I):
                check(str(PurePosixPath(name).parent), reference)

def build(root, output):
    config = json.loads((root / 'release.json').read_text(encoding='utf-8'))
    addon = config['addon']
    if not re.fullmatch(r'EzWoW-[A-Za-z]+', addon):
        raise ValueError('Invalid addon folder name')
    toc_path = root / (addon + '.toc')
    toc = toc_path.read_text(encoding='utf-8-sig')
    def field(name):
        found = re.search(r'^##\s*' + re.escape(name) + r':\s*(.+?)\s*$', toc, re.M)
        if not found:
            raise ValueError('Missing TOC metadata: ' + name)
        return found.group(1)
    version = field('Version')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)+(?:[-+][A-Za-z0-9.-]+)?', version):
        raise ValueError('Invalid release version')
    if int(field('X-Curse-Project-ID')) != config['project_id']:
        raise ValueError('TOC and release.json project IDs differ')
    if field('Interface') != config['interface']:
        raise ValueError('TOC and release.json interface versions differ')
    files = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(part in EXCLUDED or part.startswith('.') for part in relative.parts):
            continue
        if path.is_file() and (path.suffix.lower() in EXTENSIONS or path.name.startswith(('LICENSE', 'COPYING'))):
            if path.is_symlink():
                raise ValueError('Symlinks are not supported: ' + str(relative))
            files[relative.as_posix()] = path
    validate_references(files, toc)
    output.mkdir(parents=True, exist_ok=True)
    archive = output / (addon + '-v' + version + '-forever.zip')
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as target:
        for relative, source in files.items():
            info = zipfile.ZipInfo(addon + '/' + relative, (2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            target.writestr(info, source.read_bytes())
    with zipfile.ZipFile(archive) as target:
        if target.testzip() is not None or addon + '/' + addon + '.toc' not in target.namelist():
            raise ValueError('ZIP verification failed')
    changelog_path = root / 'RELEASE_NOTES.md'
    changelog = changelog_path.read_text(encoding='utf-8-sig')
    if not re.search(r'^#\s+v?' + re.escape(version) + r'\s*$', changelog, re.M):
        raise ValueError('RELEASE_NOTES.md must have a heading matching the TOC version: # v' + version)
    metadata = {'displayName': 'v' + version + '-forever', 'changelog': changelog, 'changelogType': 'markdown',
                'gameVersionNames': [config['game_version']], 'releaseType': 'release'}
    metadata_path = archive.with_suffix('.metadata.json')
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.sha256').write_text(digest + '  ' + archive.name + '\n', encoding='ascii')
    return archive, metadata, config, len(files), digest

def upload(archive, metadata, config):
    token = os.environ.get('CF_API_TOKEN')
    if not token:
        raise ValueError('Set CF_API_TOKEN to use --upload. Never commit tokens.')
    boundary = '----EzWoW' + uuid.uuid4().hex
    body = ('--' + boundary + '\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json\r\n\r\n').encode()
    body += json.dumps(metadata, ensure_ascii=False).encode() + b'\r\n'
    body += ('--' + boundary + '\r\nContent-Disposition: form-data; name="file"; filename="' + archive.name + '"\r\nContent-Type: application/zip\r\n\r\n').encode()
    body += archive.read_bytes() + ('\r\n--' + boundary + '--\r\n').encode()
    request = urllib.request.Request('https://wow.curseforge.com/api/projects/' + str(config['project_id']) + '/upload-file', data=body,
        headers={'X-Api-Token': token, 'Content-Type': 'multipart/form-data; boundary=' + boundary}, method='POST')
    # Do not retry uploads automatically: a timeout may occur after acceptance.
    with urllib.request.urlopen(request, timeout=180) as response:
        result = json.load(response)
    if not isinstance(result.get('id'), int):
        raise ValueError('Upload response did not include a CurseForge file ID')
    archive.with_suffix('.upload.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('CurseForge file ID:', result['id'])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--upload', action='store_true', help='Publish using CF_API_TOKEN; default is build only')
    parser.add_argument('--github-release', action='store_true', help='Use the published GitHub release tag, notes and prerelease flag')
    args = parser.parse_args()
    root = args.root.resolve()
    archive, metadata, config, count, digest = build(root, args.output.resolve() if args.output else root / 'dist')
    if args.github_release:
        event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text(encoding='utf-8'))
        release = event.get('release', {})
        version = metadata['displayName'].removesuffix('-forever')
        if release.get('tag_name') not in (version, version[1:], version + '-forever'):
            raise ValueError('GitHub release tag must match the TOC version: ' + version)
        if release.get('draft'):
            raise ValueError('Draft releases cannot be uploaded')
        # Public release notes come from the versioned repository file, never CI instructions.
        metadata['releaseType'] = 'beta' if release.get('prerelease') else 'release'
        archive.with_suffix('.metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'zip': str(archive), 'files': count, 'project_id': config['project_id'], 'sha256': digest}, ensure_ascii=False))
    if args.upload:
        upload(archive, metadata, config)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, urllib.error.URLError) as error:
        print('Release failed:', error, file=sys.stderr)
        sys.exit(1)
