"""Exercise a downloaded art bundle without a game install or Klei SDK.

All extraction, mutation and generated outputs stay inside a new research temp
directory. This can run on Windows, macOS or Linux; the report records the actual
host and does not treat a Windows run as proof of execution on another OS.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def tree_hashes(directory):
    return {path.relative_to(directory).as_posix(): digest(path)
            for path in sorted(directory.rglob('*')) if path.is_file()}


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def extract(archive, destination):
    destination.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        for entry in source.namelist():
            target = (destination / entry).resolve()
            check(target.is_relative_to(destination.resolve()),
                  f'Archive entry escapes extraction directory: {entry}')
        source.extractall(destination)


class PortableChecks:
    def __init__(self, bundle, working, expected_revision=None, check_builders=False):
        self.bundle = bundle
        self.working = working
        self.cwd = working / 'outside bundle cwd'
        self.cwd.mkdir()
        self.logs = working / 'logs'
        self.logs.mkdir()
        self.missing_sdk = working / 'definitely missing Klei SDK'
        check(not self.missing_sdk.exists(), 'The test SDK path must not exist')
        self.cases = []
        self.commands = []
        self.source = working / 'downloaded bundle with spaces'
        self.index = None
        self.expected_revision = expected_revision
        self.check_builders = check_builders

    def passed(self, name, **details):
        self.cases.append({'name': name, 'status': 'passed', **details})
        print(f'PASS {name}', flush=True)

    def run(self, source, name, *arguments, succeeds=True, contains=None,
            explicit_sdk=True, script='tools/package_arcane_storage_art.py'):
        check(not self.cwd.is_relative_to(source), 'Process cwd must be outside the extracted bundle')
        command = [sys.executable, str(source / script), *arguments]
        if explicit_sdk:
            command.extend(['--tools', str(self.missing_sdk)])
        environment = dict(os.environ, DST_MOD_TOOLS=str(self.missing_sdk),
                           PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
        started = time.monotonic()
        completed = subprocess.run(command, cwd=self.cwd, env=environment,
                                   text=True, encoding='utf-8', errors='replace',
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   timeout=240)
        log = self.logs / f'{len(self.commands) + 1:02d}_{name}.log'
        log.write_text(completed.stdout, encoding='utf-8')
        self.commands.append({'name': name, 'command': command, 'cwd': str(self.cwd),
                              'returncode': completed.returncode,
                              'seconds': round(time.monotonic() - started, 3),
                              'log': str(log)})
        check((completed.returncode == 0) == succeeds,
              f'{name}: unexpected exit {completed.returncode}; see {log}\n{completed.stdout}')
        if contains is not None:
            check(contains in completed.stdout,
                  f'{name}: expected {contains!r}; see {log}\n{completed.stdout}')
        return completed

    @contextmanager
    def restore_after(self, path):
        check(path.resolve().is_relative_to(self.working.resolve()),
              'Tests may only mutate their isolated extracted files')
        original = path.read_bytes()
        try:
            yield
        finally:
            path.write_bytes(original)

    def assert_repack(self, source):
        package = source / 'package'
        report = read_json(package / 'validation/report.json')
        check(report['status'] == 'verified_precompiled_repack', 'Incorrect repack status')
        check(report['native_recompiled_this_run'] is False, 'Repack must not compile native assets')
        generated = package / 'arcane_storage_art_bundle.zip'
        revision = self.index.get('art_revision')
        if revision is not None:
            check(report.get('art_revision') == revision, 'Repack report changed the art revision')
            generated = package/f'arcane_storage_art_{revision}_portable.zip'
            for alias in (f'arcane_storage_art_{revision}.zip', 'arcane_storage_art_bundle.zip'):
                check(digest(package/alias) == digest(generated), f'Download alias differs: {alias}')
            check((package/f'review_{revision}.html').read_bytes() == (package/'review.html').read_bytes(),
                  'Versioned preview and generic preview differ')
        with zipfile.ZipFile(generated) as archive:
            entries = archive.namelist()
            check(len(entries) == len(set(entries)), 'Generated ZIP contains duplicate entries')
            check(not any(entry.startswith('package/') or
                          (Path(entry).name.startswith('arcane_storage_art_') and entry.endswith('.zip'))
                          for entry in entries), 'Generated ZIP recursively includes package outputs')
            check(archive.testzip() is None, 'Generated ZIP has a CRC failure')
            index = json.loads(archive.read('portable_manifest.json'))
            if revision is not None:
                check(index.get('art_revision') == revision, 'Repack index changed the art revision')
                check(archive.read(f'review/review_{revision}.html') == archive.read('review/review.html'),
                      'ZIP preview aliases differ')
                check(revision.upper().encode() in archive.read('BUILD.txt'), 'Build guide lacks release version')
                if revision != 'r2':
                    check(b'export_r2_extinguish.py' not in archive.read('BUILD.txt'),
                          'New-release guide still runs the obsolete R2 preview export')
            for section in ('inputs', 'outputs'):
                for relative, expected in index[section].items():
                    check(hashlib.sha256(archive.read(relative)).hexdigest() == expected,
                          f'Generated index does not match {relative}')
            for relative, expected in self.index['outputs'].items():
                if relative.startswith(('runtime/', 'animation_source/')):
                    check(hashlib.sha256(archive.read(relative)).hexdigest() == expected,
                          f'Repack changed compiled resource: {relative}')
        return generated

    def rejects_without_writes(self, source, name, expected, *arguments):
        before = tree_hashes(source / 'package')
        self.run(source, name, *arguments, succeeds=False, contains=expected)
        check(tree_hashes(source / 'package') == before,
              f'{name}: rejection modified existing package files')

    def check_subset_whitelist(self):
        # Exercise selection with pre-existing full-build outputs. No compiler is
        # run here; the shared atlas is only a fixture for this archive test.
        stage = self.working / 'subset packaging fixture'
        shutil.copytree(self.source / 'package', stage,
                        ignore=shutil.ignore_patterns('arcane_storage_art_*.zip'))
        report = read_json(stage / 'validation/report.json')
        selected_name = self.index['assets'][0]
        selected_bank = read_json(self.source / selected_name / 'clip_manifest.json')['bank']
        selected_reports = [row for row in report['assets'] if row['bank'] == selected_bank]
        stale_banks = {row['bank'] for row in report['assets']} - {selected_bank}
        check(stale_banks and all((stage / 'anim' / f'{bank}.zip').exists() for bank in stale_banks),
              'Subset test requires existing outputs from the other asset')
        report['assets'] = selected_reports
        (stage / 'validation/report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2),
                                                     encoding='utf-8')
        sys.path.insert(0, str(self.source / 'tools'))
        try:
            spec = importlib.util.spec_from_file_location(
                'portable_bundle_under_test', self.source / 'tools/package_arcane_storage_art.py')
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            module.write_viewer(stage, [selected_name])
            generated = module.write_bundle(stage, [selected_name], selected_reports, report['inventory'])
        finally:
            sys.path.pop(0)
        with zipfile.ZipFile(generated) as archive:
            entries = archive.namelist()
            check({entry for entry in entries if entry.startswith('runtime/anim/')} ==
                  {f'runtime/anim/{selected_bank}.zip'}, 'Subset ZIP includes a stale runtime bank')
            check({entry for entry in entries if entry.startswith('animation_source/')} ==
                  {f'animation_source/{selected_bank}.zip'}, 'Subset ZIP includes stale compiler sources')
            check(not any(entry.startswith(f'validation/{bank}_')
                          for bank in stale_banks for entry in entries),
                  'Subset ZIP includes another asset\'s validation outputs')
            check(json.loads(archive.read('portable_manifest.json'))['assets'] == [selected_name],
                  'Subset portable index selects the wrong assets')
        self.passed('subset_zip_excludes_stale_bank', selected_bank=selected_bank,
                    excluded_banks=sorted(stale_banks), native_compilation_performed=False)

    def check_source_builders(self):
        source = self.working/'PNG rebuild bundle with spaces'
        extract(self.bundle, source)
        before = {path.relative_to(source).as_posix(): digest(path)
                  for asset in self.index['assets'] for folder in ('world', 'inventory')
                  for path in (source/asset/folder).glob('*.png')}
        manifests = {f'{asset}/clip_manifest.json': digest(source/asset/'clip_manifest.json')
                     for asset in self.index['assets']}
        provenance = {path.relative_to(source).as_posix(): digest(path)
                      for asset in self.index['assets']
                      for path in (source/asset).glob('*manifest.json')
                      if path.name != 'clip_manifest.json'}
        for name, script in (
                ('rebuild_dustbox', 'tools/build_dustbox_jewellery_art.py'),
                ('rebuild_emberlamp', 'tools/build_emberlamp_art.py'),
                ('rebuild_lamp_inventory', 'emberlamp/export_inventory.py')):
            self.run(source, name, script=script, explicit_sdk=False)
        changed_pngs = [relative for relative, expected in before.items()
                        if digest(source/relative) != expected]
        check(not changed_pngs, f'Builder output PNG bytes changed: {changed_pngs}')
        changed_manifests = [relative for relative, expected in manifests.items()
                            if digest(source/relative) != expected]
        check(not changed_manifests, f'Builder changed bound clip manifests: {changed_manifests}')
        changed_provenance = [relative for relative, expected in provenance.items()
                             if digest(source/relative) != expected]
        self.passed('standalone_source_builders_preserve_exported_bytes',
                    unchanged_world_pngs=sum('/world/' in path for path in before),
                    unchanged_inventory_pngs=sum('/inventory/' in path for path in before),
                    unchanged_clip_manifests=len(manifests),
                    changed_unbound_provenance=changed_provenance)
        self.run(source, 'repack_after_source_builders',
                 contains='no compiler or game installation used')
        self.assert_repack(source)
        self.passed('default_repack_after_source_rebuild_without_sdk')

    def execute(self):
        extract(self.bundle, self.source)
        self.index = read_json(self.source / 'portable_manifest.json')
        if self.expected_revision:
            check(self.index.get('art_revision') == self.expected_revision,
                  f'Expected {self.expected_revision}, got {self.index.get("art_revision")!r}')
        pngs = {relative: digest(self.source / relative) for relative in self.index['inputs']
                if relative.endswith('.png')}
        check(pngs, 'No source PNG inputs found in portable index')
        preserved = {}
        if self.index.get('art_revision') not in (None, 'r2'):
            # Simulate named R2 downloads beside a later release. Packaging may
            # refresh the latest alias, but must leave these historical files.
            package = self.source/'package'
            package.mkdir()
            for name in ('arcane_storage_art_r2.zip', 'arcane_storage_art_r2_portable.zip'):
                with zipfile.ZipFile(package/name, 'w') as archive:
                    archive.writestr('README.txt', 'Preserved previous-release test fixture')
                preserved[name] = digest(package/name)
            (package/'review_r2.html').write_text('Preserved R2 preview fixture', encoding='utf8')
            preserved['review_r2.html'] = digest(package/'review_r2.html')

        # This is the exact default command: SDK location is invalid through the
        # environment. The next run also passes a nonexistent --tools explicitly.
        self.run(self.source, 'default_outside_cwd', explicit_sdk=False,
                 contains='no compiler or game installation used')
        self.assert_repack(self.source)
        self.passed('default_repack_without_sdk', source_pngs=len(pngs))
        if preserved:
            check(all(digest(self.source/'package'/name) == expected for name, expected in preserved.items()),
                  'New release overwrote a previous-release ZIP or preview')
            self.passed('previous_revision_downloads_preserved', files=sorted(preserved))
        if self.index.get('art_revision'):
            self.passed('release_metadata_preview_and_download_aliases', revision=self.index['art_revision'])

        self.run(self.source, 'repeat_default', contains='no compiler or game installation used')
        first_generation = self.assert_repack(self.source)
        self.passed('repeat_repack_with_missing_tools')

        second = self.working / 'second generation bundle with spaces'
        extract(first_generation, second)
        self.run(second, 'second_generation', contains='no compiler or game installation used')
        self.assert_repack(second)
        self.passed('second_generation_repack')

        relative_png = next(iter(pngs))
        png = self.source / relative_png
        with self.restore_after(png):
            with Image.open(png) as opened:
                modified = opened.copy()
            pixels = modified.load()
            coordinate = next((x, y) for y in range(modified.height)
                              for x in range(modified.width) if pixels[x, y][3] > 0)
            red, green, blue, alpha = pixels[coordinate]
            pixels[coordinate] = ((red + 1) % 256, green, blue, alpha)
            modified.save(png)
            self.rejects_without_writes(self.source, 'modified_png',
                                        f'Bundled inputs changed: {relative_png}')
            self.passed('modified_png_rejected_without_output_changes', file=relative_png)
            native_before = {relative: digest(self.source / 'package' / relative)
                             for relative in tree_hashes(self.source / 'package')
                             if relative.startswith(('anim/', 'images/', 'source/')) or
                             (relative.startswith('arcane_storage_art_') and relative.endswith('.zip'))}
            self.run(self.source, 'edited_png_preview', '--preview-only', contains='Preview only')
            check((self.source / 'package/review.html').is_file(), 'Preview did not create viewer')
            check(all(digest(self.source / 'package' / relative) == expected
                      for relative, expected in native_before.items()),
                  'Preview-only modified native resources or the existing ZIP')
            self.passed('edited_png_preview_without_sdk')

        asset = self.index['assets'][0]
        manifest = self.source / asset / 'clip_manifest.json'
        with self.restore_after(manifest):
            data = read_json(manifest)
            clip = next(iter(data['clips']))
            data['clips'][clip]['fps'] = 29 if data['clips'][clip]['fps'] != 29 else 28
            manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
            self.rejects_without_writes(self.source, 'modified_manifest_fps',
                                        f'Bundled inputs changed: {asset}/clip_manifest.json')
            self.passed('modified_manifest_fps_rejected_without_output_changes', clip=clip)

        relative_runtime = next(relative for relative in self.index['outputs']
                                if relative.startswith('runtime/anim/'))
        runtime = self.source / relative_runtime
        with self.restore_after(runtime):
            runtime.write_bytes(runtime.read_bytes() + b'\nportable-regression-mutation\n')
            self.rejects_without_writes(self.source, 'modified_runtime',
                                        f'Bundled outputs changed: {relative_runtime}')
            self.passed('modified_runtime_rejected_without_output_changes', file=relative_runtime)

        self.rejects_without_writes(self.source, 'partial_cache_rejected',
                                    'inventory atlas is shared', '--asset', asset)
        self.passed('partial_cached_repack_rejected')

        expected = ('Klei toolchain not found' if sys.platform == 'win32'
                    else 'Native recompilation currently uses the Windows Klei toolchain')
        self.rejects_without_writes(self.source, 'missing_sdk_recompile', expected, '--recompile')
        self.passed('explicit_recompile_requires_sdk')

        self.check_subset_whitelist()
        check(all(digest(self.source / relative) == expected for relative, expected in pngs.items()),
              'The regression run changed original source PNGs')
        self.passed('source_png_bytes_preserved', unchanged_png_count=len(pngs))
        if self.check_builders:
            self.check_source_builders()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path,
                        default=ROOT / 'assets_src/arcane_storage_final/package/arcane_storage_art_r3_portable.zip')
    parser.add_argument('--expect-revision', help='Require this art_revision in the source portable index')
    parser.add_argument('--check-builders', action='store_true',
                        help='Also rebuild world/UI PNGs in a separate extraction and repackage them')
    parser.add_argument('--report', type=Path, help='Also write the result JSON to this path')
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    check(bundle.is_file(), f'Missing bundle: {bundle}')
    research = ROOT / 'research'
    research.mkdir(exist_ok=True)
    working = Path(tempfile.mkdtemp(prefix='portable integration ', dir=research))
    tests = PortableChecks(bundle, working, args.expect_revision, args.check_builders)
    started = time.monotonic()
    result = {'source_bundle': str(bundle), 'source_bundle_sha256': digest(bundle),
              'host_platform': sys.platform, 'host_description': platform.platform(),
              'python': sys.version, 'working_directory': str(working),
              'outside_bundle_cwd': str(tests.cwd), 'missing_sdk': str(tests.missing_sdk),
              'scope': 'Execution on the recorded host only; other operating systems were not run.'}
    failure = None
    try:
        tests.execute()
    except Exception as error:
        failure = f'{type(error).__name__}: {error}'
    result.update({'status': 'failed' if failure else 'passed', 'error': failure,
                   'seconds': round(time.monotonic() - started, 3),
                   'passed_case_count': len(tests.cases), 'subprocess_count': len(tests.commands),
                   'cases': tests.cases, 'commands': tests.commands})
    report = working / 'integration_report.json'
    encoded = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    report.write_text(encoded, encoding='utf-8')
    if args.report:
        args.report.resolve().parent.mkdir(parents=True, exist_ok=True)
        args.report.resolve().write_text(encoded, encoding='utf-8')
    print(json.dumps({'status': result['status'], 'passed_cases': len(tests.cases),
                      'subprocesses': len(tests.commands), 'report': str(report)}, indent=2))
    if failure:
        raise SystemExit(failure)


if __name__ == '__main__':
    main()
