#!/usr/bin/env python3
"""Portable metadata validation and XML rendering; no signing credentials."""
import base64
import os
from pathlib import Path
import plistlib
import re
import sys
import tempfile
from urllib.parse import quote
import xml.etree.ElementTree as ET
import zipfile

SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
RELEASES = 'https://github.com/szryldrm/vesila-mac/releases'
ET.register_namespace('sparkle', SPARKLE)


def public_key(value):
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, TypeError):
        raise ValueError('Missing, placeholder, or malformed Sparkle public key') from None
    if len(decoded) != 32 or not any(decoded):
        raise ValueError('Missing, placeholder, or malformed Sparkle public key')
    return value


def validate_versions(version, build):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?', version):
        raise ValueError('Expected a semantic VERSION, e.g. 1.0.3')
    if not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('BUILD_NUMBER must be a positive integer')


def metadata(archive, version, build, root):
    validate_versions(version, build)
    with zipfile.ZipFile(archive) as bundle:
        names = bundle.namelist()
        if names.count('Vesila.app/Contents/Info.plist') != 1:
            raise ValueError('ZIP must contain exactly one top-level Vesila.app')
        if any(not (n.startswith('Vesila.app/') or n.startswith('__MACOSX/')) for n in names):
            raise ValueError('Unexpected top-level ZIP content')
        if any('..' in Path(n).parts or n.startswith('/') for n in names):
            raise ValueError('Unsafe ZIP path')
        info = plistlib.loads(bundle.read('Vesila.app/Contents/Info.plist'))
    if info.get('CFBundleIdentifier') != 'com.sezeryildirim.vesila':
        raise ValueError('Wrong bundle identifier')
    if (info.get('CFBundleShortVersionString'), info.get('CFBundleVersion')) != (version, build):
        raise ValueError('VERSION/BUILD_NUMBER mismatch with archived bundle')
    if info.get('LSMinimumSystemVersion') != '14.0':
        raise ValueError('Archived bundle must target macOS 14.0')
    key = os.environ.get('SPARKLE_PUBLIC_ED_KEY')
    if key is None:
        key = (Path(root) / 'Packaging/SparklePublicEDKey').read_text().strip()
    key = public_key(key)
    if info.get('SUPublicEDKey') != key:
        raise ValueError('Archived bundle public key differs from configured key')
    return key


def render(archive, version, build, signature, output):
    validate_versions(version, build)
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Expected a 64-byte EdDSA signature')
    length = Path(archive).stat().st_size
    if length == 0:
        raise ValueError('Empty update archive')
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'Vesila Updates'
    ET.SubElement(channel, 'link').text = RELEASES
    ET.SubElement(channel, 'description').text = 'Stable Vesila releases'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = f'Vesila {version}'
    for name, value in [('version', build), ('shortVersionString', version), ('minimumSystemVersion', '14.0')]:
        ET.SubElement(item, f'{{{SPARKLE}}}{name}').text = value
    ET.SubElement(item, 'enclosure', {
        'url': f'{RELEASES}/download/v{quote(version, safe="")}/{quote(Path(archive).name, safe="")}',
        f'{{{SPARKLE}}}edSignature': signature,
        'length': str(length), 'type': 'application/octet-stream',
    })
    # Parse our serialized output before atomically replacing a previously valid feed.
    data = ET.tostring(rss, encoding='utf-8', xml_declaration=True)
    ET.fromstring(data)
    output = Path(output)
    if output.resolve() == Path(archive).resolve():
        raise ValueError('Output must not overwrite the update archive')
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as temp:
        temp.write(data + b'\n')
    try:
        os.replace(temp.name, output)
    finally:
        Path(temp.name).unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'metadata' and len(sys.argv) == 6:
            print(metadata(*sys.argv[2:]))
        elif sys.argv[1] == 'render' and len(sys.argv) == 7:
            render(*sys.argv[2:])
        else:
            raise ValueError('Use metadata ARCHIVE VERSION BUILD ROOT or render ARCHIVE VERSION BUILD SIGNATURE OUTPUT')
    except (ValueError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        sys.exit(f'Appcast error: {error}')
