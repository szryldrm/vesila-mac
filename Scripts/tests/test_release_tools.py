"""Linux checks for release metadata/XML and shell orchestration; macOS tools are mocked."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('appcast', ROOT / 'Scripts/appcast.py')
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)
PUBLIC = base64.b64encode(bytes(range(32))).decode()
SIGNATURE = base64.b64encode(bytes(range(64))).decode()


class ReleaseToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('PAPERCLIP_RUN_SCRATCH_DIR'))
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.info = dict(CFBundleIdentifier='com.sezeryildirim.vesila',
                         CFBundleShortVersionString='1.0.4', CFBundleVersion='104',
                         LSMinimumSystemVersion='14.0', SUPublicEDKey=PUBLIC)
        self.archive = self.path / 'Vesila 1.0.4.zip'
        self.write_zip()
        self.env = patch.dict(os.environ, SPARKLE_PUBLIC_ED_KEY=PUBLIC)
        self.env.start()
        self.addCleanup(self.env.stop)

    def write_zip(self):
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('Vesila.app/Contents/Info.plist', plistlib.dumps(self.info))

    def test_metadata_from_actual_archive(self):
        self.assertEqual(appcast.metadata(self.archive, '1.0.4', '104', ROOT), PUBLIC)

    def test_version_and_build_mismatch(self):
        for version, build in [('1.0.3', '104'), ('1.0.4', '103')]:
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                appcast.metadata(self.archive, version, build, ROOT)

    def test_missing_placeholder_and_wrong_keys(self):
        for key in ['', 'REPLACE_WITH_PUBLIC_KEY', base64.b64encode(bytes(32)).decode()]:
            with patch.dict(os.environ, SPARKLE_PUBLIC_ED_KEY=key):
                with self.assertRaisesRegex(ValueError, 'public key'):
                    appcast.metadata(self.archive, '1.0.4', '104', ROOT)
        self.info['SUPublicEDKey'] = base64.b64encode(bytes([42] * 32)).decode()
        self.write_zip()
        with self.assertRaisesRegex(ValueError, 'differs'):
            appcast.metadata(self.archive, '1.0.4', '104', ROOT)

    def test_render_valid_xml_and_exact_contract(self):
        output = self.path / 'appcast.xml'
        appcast.render(self.archive, '1.0.4', '104', SIGNATURE, output)
        item = ET.parse(output).find('./channel/item')
        ns = '{' + appcast.SPARKLE + '}'
        self.assertEqual(item.find(ns + 'version').text, '104')
        self.assertEqual(item.find(ns + 'shortVersionString').text, '1.0.4')
        self.assertEqual(item.find(ns + 'minimumSystemVersion').text, '14.0')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('url'), appcast.RELEASES + '/download/v1.0.4/Vesila%201.0.4.zip')
        self.assertEqual(enclosure.get(ns + 'edSignature'), SIGNATURE)
        self.assertEqual(int(enclosure.get('length')), self.archive.stat().st_size)

    def test_bad_signature_preserves_old_feed(self):
        output = self.path / 'appcast.xml'
        output.write_text('previous feed')
        with self.assertRaises(ValueError):
            appcast.render(self.archive, '1.0.4', '104', 'bad', output)
        self.assertEqual(output.read_text(), 'previous feed')

    def test_output_cannot_overwrite_archive(self):
        before = self.archive.read_bytes()
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            appcast.render(self.archive, '1.0.4', '104', SIGNATURE, self.archive)
        self.assertEqual(before, self.archive.read_bytes())

    def test_wrong_bundle_and_unsafe_zip(self):
        self.info['CFBundleIdentifier'] = 'other.app'
        self.write_zip()
        with self.assertRaisesRegex(ValueError, 'identifier'):
            appcast.metadata(self.archive, '1.0.4', '104', ROOT)
        self.info['CFBundleIdentifier'] = 'com.sezeryildirim.vesila'
        self.write_zip()
        with zipfile.ZipFile(self.archive, 'a') as archive:
            archive.writestr('Vesila.app/../outside', b'bad')
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            appcast.metadata(self.archive, '1.0.4', '104', ROOT)

    def fixture_signing(self):
        app = self.path / 'Vesila.app'
        contents = app / 'Contents'
        contents.mkdir(parents=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps(self.info))
        framework = contents / 'Frameworks/Sparkle.framework'
        version = framework / 'Versions/B'
        (version / 'XPCServices/Downloader.xpc').mkdir(parents=True)
        (version / 'XPCServices/Installer.xpc').mkdir()
        (version / 'Updater.app').mkdir()
        (version / 'Autoupdate').write_text('fixture')
        (framework / 'Versions/Current').symlink_to('B')
        bin_dir = self.path / 'bin'
        bin_dir.mkdir()
        mock = bin_dir / 'codesign'
        mock.write_text('#!/usr/bin/env python3\nimport os,sys,json\nwith open(os.environ["SIGN_LOG"], "a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
        mock.chmod(0o755)
        env = dict(os.environ, PATH=str(bin_dir) + ':' + os.environ['PATH'],
                   APP_BUNDLE=str(app), DEVELOPER_ID_APPLICATION='Fixture Developer ID',
                   SIGN_LOG=str(self.path / 'sign.log'))
        env.pop("BASH_ENV", None)  # Hermetic mocks; runner startup files reset PATH.
        return app, version, env

    def test_inside_out_signing_and_verification(self):
        app, version, env = self.fixture_signing()
        subprocess.run(['bash', str(ROOT / 'Scripts/sign_app.sh')], env=env, check=True, capture_output=True)
        calls = [json.loads(line) for line in (self.path / 'sign.log').read_text().splitlines()]
        signing = [c for c in calls if '--sign' in c]
        self.assertEqual([Path(c[-1]).name for c in signing],
                         ['Downloader.xpc', 'Installer.xpc', 'Autoupdate', 'Updater.app', 'Sparkle.framework', 'Vesila.app'])
        for c in signing:
            self.assertIn('runtime', c)
            self.assertIn('--timestamp', c)
            self.assertNotIn('--deep', c)
        self.assertIn('--entitlements', signing[-1])
        self.assertTrue(all('--entitlements' not in c for c in signing[:-1]))
        self.assertEqual(len([c for c in calls if '--verify' in c]), 6)

    def test_missing_component_fails_before_any_signing(self):
        _, version, env = self.fixture_signing()
        (version / 'Autoupdate').unlink()
        result = subprocess.run(['bash', str(ROOT / 'Scripts/sign_app.sh')], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.path / 'sign.log').exists())

    def test_missing_identity_and_placeholder_bundle_fail(self):
        app, _, env = self.fixture_signing()
        env.pop('DEVELOPER_ID_APPLICATION')
        result = subprocess.run(['bash', str(ROOT / 'Scripts/sign_app.sh')], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        env['DEVELOPER_ID_APPLICATION'] = 'Fixture Developer ID'
        self.info['SUPublicEDKey'] = 'PLACEHOLDER'
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.info))
        result = subprocess.run(['bash', str(ROOT / 'Scripts/sign_app.sh')], env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.path / 'sign.log').exists())


    def fixture_appcast_tools(self):
        _, _, env = self.fixture_signing()
        mock_dir = self.path / 'bin'
        # Every mock call is logged, including stdin use, without recording private input.
        mock_source = """#!/usr/bin/env python3
import json, os, sys, zipfile
from pathlib import Path
name = Path(sys.argv[0]).name
with open(os.environ['TOOL_LOG'], 'a') as file:
    file.write(json.dumps([name] + sys.argv[1:]) + '\\n')
if name == 'ditto':
    with zipfile.ZipFile(sys.argv[-2]) as archive:
        archive.extractall(sys.argv[-1])
elif name == 'sign_update':
    if '--ed-key-file' in sys.argv and '-' in sys.argv:
        assert sys.stdin.read().strip() == 'fixture-input'
    if os.environ.get('FAIL_SIGN'):
        print('sensitive-fixture-diagnostic')
        print('sensitive-fixture-diagnostic', file=sys.stderr)
        sys.exit(1)
    print(os.environ['DUMMY_SIGNATURE'])
elif name == 'swift':
    assert sys.argv[-2] == os.environ['SPARKLE_PUBLIC_ED_KEY']
    if os.environ.get('FAIL_VERIFY'):
        sys.exit(1)
"""
        for name in ['ditto', 'sign_update', 'swift', 'spctl', 'xcrun']:
            script = mock_dir / name
            script.write_text(mock_source)
            script.chmod(0o755)
        env.update(SPARKLE_BIN=str(mock_dir), DUMMY_SIGNATURE=SIGNATURE,
                   TOOL_LOG=str(self.path / 'tools.log'))
        env.pop('SPARKLE_PRIVATE_ED_KEY', None)
        env.pop('SPARKLE_PRIVATE_ED_KEY_FILE', None)
        return env

    def run_appcast(self, env):
        return subprocess.run(['bash', str(ROOT / 'Scripts/make_appcast.sh'),
                               str(self.archive), '1.0.4', '104', str(self.path / 'appcast.xml')],
                              env=env, capture_output=True, text=True)

    def test_appcast_shell_keychain_file_and_stdin_inputs(self):
        env = self.fixture_appcast_tools()
        for mode in ['keychain', 'file', 'stdin']:
            variant = dict(env)
            if mode == 'file':
                key_file = self.path / 'fixture-key'
                key_file.write_text('fixture-input')
                variant['SPARKLE_PRIVATE_ED_KEY_FILE'] = str(key_file)
            if mode == 'stdin':
                variant['SPARKLE_PRIVATE_ED_KEY'] = 'fixture-input'
            result = self.run_appcast(variant)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(ET.parse(self.path / 'appcast.xml').find('./channel/item').find(
                '{' + appcast.SPARKLE + '}version').text, '104')
        calls = [json.loads(line) for line in (self.path / 'tools.log').read_text().splitlines()]
        signing_calls = [c for c in calls if c[0] == 'sign_update']
        self.assertIn('--account', signing_calls[0])
        self.assertIn('--ed-key-file', signing_calls[1])
        self.assertIn('-', signing_calls[2])
        self.assertNotIn('fixture-input', str(calls))

    def test_appcast_signing_failure_does_not_publish_or_leak_diagnostics(self):
        env = self.fixture_appcast_tools()
        env.update(FAIL_SIGN='1', SPARKLE_PRIVATE_ED_KEY='fixture-input')
        output = self.path / 'appcast.xml'
        output.write_text('previous feed')
        result = self.run_appcast(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('sensitive-fixture-diagnostic', result.stdout + result.stderr)
        self.assertEqual(output.read_text(), 'previous feed')

    def test_appcast_public_key_verification_failure_preserves_feed(self):
        env = self.fixture_appcast_tools()
        env['FAIL_VERIFY'] = '1'
        output = self.path / 'appcast.xml'
        output.write_text('previous feed')
        result = self.run_appcast(env)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output.read_text(), 'previous feed')


if __name__ == '__main__':
    unittest.main()
