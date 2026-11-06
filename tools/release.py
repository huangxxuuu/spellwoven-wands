"""Version, validate, freeze, commit and publish one reproducible release.

Default mode only prints a plan. Private releases never deploy Pages. Steam
visibility is omitted from VDF unless explicitly supplied, preserving the item.
No credentials are saved; SteamCMD inherits the terminal for login/Steam Guard.
"""
from __future__ import annotations

import argparse
from datetime import date
from contextlib import contextmanager, nullcontext
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r'^version\s*=\s*"(\d+\.\d+\.\d+)"', re.M)


class ReleaseError(RuntimeError):
    pass


def require(ok, message):
    if not ok:
        raise ReleaseError(message)


@contextmanager
def release_lock(root):
    path = root / 'dist/.release.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise ReleaseError(f'Release lock exists: {path}. If the previous process crashed, verify it has stopped before removing the lock.')
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        path.unlink()


def run(args, cwd=ROOT, capture=False, check=True):
    args = [str(x) for x in args]
    print('>', subprocess.list2cmdline(args), flush=True)
    result = subprocess.run(args, cwd=cwd, text=True, encoding='utf-8',
                            errors='replace', capture_output=capture)
    if check and result.returncode:
        raise ReleaseError(f'Command failed ({result.returncode}): {args[0]}\n'
                           + (result.stderr or '') + (result.stdout or ''))
    return result


def git(path, *args):
    return run(['git', *args], path, capture=True).stdout.strip()


def gh_json(*args):
    return json.loads(run(['gh', *args], capture=True).stdout)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def save(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def current_version(root):
    matches = VERSION.findall((root / 'mod/modinfo.lua').read_text(encoding='utf-8'))
    require(len(matches) == 1, 'Expected exactly one modinfo version.')
    return matches[0]


def next_version(current, explicit=None, bump=None):
    parts = list(map(int, current.split('.')))
    if explicit is None:
        index = {'major': 0, 'minor': 1, 'patch': 2}[bump or 'patch']
        parts[index] += 1
        for i in range(index + 1, 3):
            parts[i] = 0
        explicit = '.'.join(map(str, parts))
    require(re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', explicit), 'Use a numeric X.Y.Z version.')
    require(tuple(map(int, explicit.split('.'))) > tuple(map(int, current.split('.'))),
            'New version must increase. Use --resume VERSION for a prepared release.')
    return explicit


def update_version(root, version):
    path = root / 'mod/modinfo.lua'
    text = path.read_text(encoding='utf-8')
    text, count = VERSION.subn(lambda m: f'version = "{version}"', text)
    require(count == 1, 'Cannot locate modinfo version.')
    text, count = re.subn(r'^local release_date\s*=\s*"\d{4}-\d{2}-\d{2}"',
                          f'local release_date = "{date.today().isoformat()}"', text, flags=re.M)
    require(count == 1, 'Cannot locate modinfo release date.')
    path.write_text(text, encoding='utf-8')
    readme = root / 'README.md'
    text = readme.read_text(encoding='utf-8')
    text = re.sub(r'(当前测试版为 \*\*)\d+\.\d+\.\d+(\*\*)',
                  lambda m: m[1] + version + m[2], text)
    readme.write_text(text, encoding='utf-8')
    # Historical documents and the last-upload receipt intentionally keep their versions.


def workshop_description(source, omitted):
    sections = re.split(r'(?=\[h2\])', source)
    text = ''.join(s for s in sections if not any(s.startswith(f'[h2]{h}[/h2]') for h in omitted))
    require(0 < len(text.encode('utf-8')) < 8000,
            'Steam description must be below 8000 UTF-8 bytes; shorten it or configure omitted headings.')
    return text


def vdf_quote(value):
    require('\x00' not in str(value), 'NUL is not allowed in VDF.')
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\r', '').replace('\n', '\\n') + '"'


def make_vdf(config, directory, description, notes, visibility='preserve'):
    require(str(config['publishedfileid']).isdigit() and int(config['publishedfileid']) > 0,
            'An existing Workshop item ID is required. Creating items is intentionally unsupported.')
    values = dict(appid=config['app_id'], publishedfileid=config['publishedfileid'],
                  contentfolder=(directory / 'content').as_posix(),
                  previewfile=(directory / 'preview.png').as_posix(), changenote=notes)
    # SteamCMD has no per-language metadata option. A default description would
    # overwrite English; localized titles/descriptions have their own API stage.
    if not config.get('workshop_languages'):
        values.update(title=config['title'], description=description)
    if visibility != 'preserve':
        values['visibility'] = {'public': 0, 'friends': 1, 'hidden': 2, 'unlisted': 3}[visibility]
    return '"workshopitem"\n{\n' + ''.join(f'  {vdf_quote(k)} {vdf_quote(v)}\n' for k, v in values.items()) + '}\n'


def check_audience(audience, visibility, repo):
    require(repo['visibility'] == ('PRIVATE' if audience == 'private' else 'PUBLIC'),
            f'Repository visibility is {repo["visibility"]}; expected {audience}. '
            'Change it yourself on GitHub when ready; this script never changes repository visibility.')
    require(audience == 'public' or visibility in ('preserve', 'hidden'),
            'Private release only permits preserved or hidden Steam visibility.')


def hashes(directory, paths):
    result = {}
    for relative in paths:
        path = directory / relative
        require(path.resolve().is_relative_to(directory.resolve()) and not path.is_symlink(),
                f'Unsafe release path: {relative}')
        require(path.is_file(), f'Missing release file: {relative}')
        result[relative] = digest(path)
    return result


def verify_hashes(directory, expected):
    require(hashes(directory, expected) == expected, 'Prepared files changed. Refusing to publish a mixed release.')


def validate_checkout(checkout, config):
    require((checkout / '.git').exists(), f'Not a Git checkout: {checkout}')
    remote = git(checkout, 'remote', 'get-url', 'origin')
    require(remote.removesuffix('.git').rstrip('/').endswith('/' + config['repository'])
            or remote == 'git@github.com:' + config['repository'] + '.git', 'Unexpected Git origin.')
    require(remote.startswith('https://github.com/') or remote.startswith('git@github.com:'),
            'Origin must use github.com.')
    require(git(checkout, 'branch', '--show-current') == config['branch'], 'Wrong release branch.')


def prepare(root, config, version, audience, visibility, notes):
    checkout = (root / config['export_directory']).resolve()
    require(checkout.is_relative_to((root / 'dist').resolve()), 'Export must be inside dist/.')
    directory = root / 'dist/releases' / version
    require(not directory.exists(), f'Release directory exists: {directory}. Use --resume or inspect the failed preparation.')
    if not checkout.exists():
        checkout.parent.mkdir(parents=True, exist_ok=True)
        run(['gh', 'repo', 'clone', config['repository'], checkout], root)
        tracked = git(checkout, 'ls-files', '-z').split('\0')
        save(checkout / '.nw_public_export', {'workspace': str(root), 'files': [p for p in tracked if p]})
    validate_checkout(checkout, config)
    marker = read_json(checkout / '.nw_public_export')
    require(marker['workspace'] == str(root), 'Export belongs to another workspace.')
    require(not git(checkout, 'status', '--porcelain'), 'Release checkout has changes; review them before preparing.')
    # Fetching is read-only; do not silently merge different work into a release.
    git(checkout, 'fetch', 'origin', config['branch'])
    require(git(checkout, 'rev-parse', 'HEAD') == git(checkout, 'rev-parse', f'origin/{config["branch"]}'),
            'Release checkout must match origin. Review/pull it first.')
    update_version(root, version)
    run([sys.executable, 'site/build_catalog.py'], root)
    run([sys.executable, 'tools/export_public_source.py', '--output', checkout, '--prune'], root)
    for script, extra in [('tools/run_tests.py', []), ('tools/check_art_assets.py', []),
                          ('tools/check_localization.py', []), ('site/build_catalog.py', ['--pages']),
                          ('tools/check_site_links.py', ['--directory', 'site/public']),
                          ('tools/build_package.py', [])]:
        run([sys.executable, script, *extra], checkout)
    run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_release*.py'], checkout)
    directory.mkdir(parents=True)
    shutil.copytree(checkout / 'mod', directory / 'content')
    shutil.copy2(checkout / config['preview'], directory / 'preview.png')
    package = directory / f'spellwoven-wands-{version}.zip'
    shutil.copy2(checkout / f'dist/nw_weave_dev-{version}.zip', package)
    site_zip = directory / f'field-guide-{version}.zip'
    with zipfile.ZipFile(site_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((checkout / 'site/public').rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(checkout / 'site/public').as_posix())
    description = workshop_description((checkout / config['description']).read_text(encoding='utf-8-sig'),
                                      config['description_omit_headings'])
    (directory / 'description.txt').write_text(description, encoding='utf-8')
    if config.get('workshop_languages'):
        localized = {key: config[key] for key in ('app_id', 'publishedfileid')}
        localized['languages'] = {language: {'title': row['title'],
            'description': workshop_description((checkout / row['description']).read_text(encoding='utf-8-sig'), [])}
            for language, row in config['workshop_languages'].items()}
        save(directory / 'workshop-localizations.json', localized)
        run([sys.executable, 'tools/steam_workshop_metadata.py', '--snapshot',
             directory / 'workshop-localizations.json'], checkout)
    (directory / 'notes.txt').write_text(notes, encoding='utf-8')
    (directory / 'workshop.vdf').write_text(make_vdf(config, directory, description, notes, visibility), encoding='utf-8')
    source_paths = read_json(checkout / '.nw_public_export')['files']
    state = dict(version=version, audience=audience, steam_visibility=visibility, config=config,
                 checkout=str(checkout), base_commit=git(checkout, 'rev-parse', 'HEAD'), steps={},
                 source_hashes=hashes(checkout, source_paths))
    # SteamCMD rewrites the VDF. Regenerate it from immutable inputs on each retry.
    state['artifact_hashes'] = hashes(directory, [p.relative_to(directory).as_posix()
                                                  for p in directory.rglob('*') if p.is_file() and p.name != 'workshop.vdf'])
    save(directory / 'state.json', state)
    print(f'Prepared {version}: {directory}. No commit, push or upload has run.', flush=True)
    return directory, state


def steam_upload(executable, username, directory, config, visibility):
    require(executable and Path(executable).is_file(), 'Supply --steamcmd PATH or install steamcmd on PATH.')
    require(username and re.fullmatch(r'[A-Za-z0-9_@.\-]+', username), 'Supply --steam-user (login name, not display name).')
    log = Path(executable).resolve().parent / 'logs/workshop_log.txt'
    offset = log.stat().st_size if log.exists() else 0
    (directory / 'workshop.vdf').write_text(make_vdf(config, directory,
        (directory / 'description.txt').read_text(encoding='utf-8'),
        (directory / 'notes.txt').read_text(encoding='utf-8'), visibility), encoding='utf-8')
    # Inherit stdin/stdout. Never capture the password/Steam Guard conversation.
    run([executable, '+login', username, '+workshop_build_item', directory / 'workshop.vdf', '+quit'], directory)
    require(log.exists(), f'No Steam upload log found: {log}. Upload remains unconfirmed.')
    with log.open('rb') as stream:
        stream.seek(offset if log.stat().st_size >= offset else 0)
        text = stream.read().decode('utf-8', errors='replace')
    item = re.escape(str(config['publishedfileid']))
    require(re.search(rf'Upload finished for workshop item {item}\s*:\s*OK\b', text),
            'SteamCMD exited without a confirmed OK for this item. Check SteamCMD logs; resume retries this SAME item.')
    vdf = (directory / 'workshop.vdf').read_text(encoding='utf-8')
    ids = re.findall(r'"publishedfileid"\s+"(\d+)"', vdf)
    require(ids == [str(config['publishedfileid'])], 'Unexpected Workshop ID after upload.')


def pages_deploy(config, commit, deadline_seconds=900):
    repo = config['repository']
    head = gh_json('api', f'repos/{repo}/commits/{config["branch"]}')['sha']
    require(head == commit, 'Remote branch changed before Pages deployment.')
    prior_ids = {r['databaseId'] for r in gh_json('run', 'list', '--repo', repo, '--workflow', 'pages.yml',
                 '--event', 'workflow_dispatch', '--commit', commit, '--limit', '30', '--json', 'databaseId')}
    run(['gh', 'workflow', 'run', 'pages.yml', '--repo', repo, '--ref', config['branch'],
         '-f', 'deploy_public=true'])
    deadline = time.monotonic() + deadline_seconds
    run_id = None
    while time.monotonic() < deadline:
        runs = gh_json('run', 'list', '--repo', repo, '--workflow', 'pages.yml', '--event', 'workflow_dispatch',
                       '--commit', commit, '--limit', '10', '--json', 'databaseId,status,conclusion')
        runs = [r for r in runs if r['databaseId'] not in prior_ids]
        if runs:
            run_id = runs[0]['databaseId']
            if runs[0]['status'] == 'completed':
                require(runs[0]['conclusion'] == 'success', f'Pages workflow failed: {run_id}')
                return run_id
        print(f'Waiting for Pages workflow ({run_id or "queued"})...', flush=True)
        time.sleep(10)
    raise ReleaseError(f'Pages timeout; inspect gh run view {run_id}. The release journal retains earlier successes.')


def publish(directory, state, args):
    config, checkout = state['config'], Path(state['checkout'])
    repo, version = config['repository'], state['version']
    state_path = directory / 'state.json'
    validate_checkout(checkout, config)
    verify_hashes(checkout, state['source_hashes'])
    verify_hashes(directory, state['artifact_hashes'])
    content_files = {p.relative_to(directory).as_posix() for p in (directory / 'content').rglob('*') if p.is_file()}
    require(content_files == {p for p in state['artifact_hashes'] if p.startswith('content/')},
            'Unexpected files in the frozen Steam content directory.')
    source_files = {p for p in git(checkout, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split('\0')
                    if p and (checkout / p).is_file()}
    require(source_files == set(state['source_hashes']), 'Unexpected source files in the release checkout.')
    check_audience(state['audience'], state['steam_visibility'],
                   gh_json('repo', 'view', repo, '--json', 'visibility'))
    native = getattr(args, 'steam_backend', 'steamcmd') == 'native'
    executable = args.steamcmd or shutil.which('steamcmd') or shutil.which('steamcmd.exe')
    if native:
        require(state['steam_visibility'] == 'preserve', 'Native upload preserves current Steam visibility.')
    else:
        require(executable and Path(executable).is_file(), 'SteamCMD not found; pass --steamcmd PATH.')
        executable = str(Path(executable).resolve())
        require(args.steam_user, 'Pass --steam-user LOGIN (or set STEAM_USER). Passwords are never stored.')
    if state['audience'] == 'public':
        # Public Pages must already be deliberately enabled by the owner.
        pages = gh_json('api', f'repos/{repo}/pages')
        require(pages.get('build_type') == 'workflow', 'Configure GitHub Pages to use GitHub Actions first.')

    def step(name, action):
        if name not in state['steps']:
            state['steps'][name] = action() or True
            save(state_path, state)

    def commit_source():
        head = git(checkout, 'rev-parse', 'HEAD')
        if head == state['base_commit']:
            git(checkout, 'add', '--all')
            git(checkout, 'commit', '-m', f'Release v{version}')
        else:
            require(git(checkout, 'log', '-1', '--format=%s') == f'Release v{version}'
                    and git(checkout, 'rev-parse', 'HEAD^') == state['base_commit'],
                    'Checkout advanced outside this release.')
        require(not git(checkout, 'status', '--porcelain'), 'Uncommitted files remain after release commit.')
        return git(checkout, 'rev-parse', 'HEAD')

    step('commit', commit_source)
    require(git(checkout, 'rev-parse', 'HEAD') == state['steps']['commit'], 'Checkout no longer matches the release commit.')
    tag = f'v{version}'

    def push_source():
        existing = run(['git', 'rev-parse', '--verify', f'refs/tags/{tag}'], checkout, capture=True, check=False)
        if existing.returncode:
            git(checkout, 'tag', '-a', tag, '-m', f'Release {tag}')
        require(git(checkout, 'rev-list', '-n', '1', tag) == state['steps']['commit'], 'Tag already points at another commit.')
        # No force pushes; remote divergence or a different tag aborts atomically.
        git(checkout, 'push', '--atomic', 'origin', f'HEAD:refs/heads/{config["branch"]}', f'refs/tags/{tag}')

    step('push', push_source)

    def draft_release():
        found = run(['gh', 'release', 'view', tag, '--repo', repo, '--json', 'isDraft,tagName'], capture=True, check=False)
        if found.returncode == 0:
            require(json.loads(found.stdout)['isDraft'], 'A published GitHub release already exists; refusing to replace its assets.')
        else:
            run(['gh', 'release', 'create', tag, '--repo', repo, '--verify-tag', '--draft',
                 '--title', f'织法之杖 {tag}', '--notes-file', directory / 'notes.txt'])
        assets = [directory / f'spellwoven-wands-{version}.zip', directory / f'field-guide-{version}.zip']
        checksum = directory / 'SHA256SUMS.txt'
        checksum.write_text(''.join(f'{digest(p)}  {p.name}\n' for p in assets), encoding='utf-8')
        run(['gh', 'release', 'upload', tag, *assets, checksum, '--repo', repo, '--clobber'])

    step('github_draft', draft_release)
    if native:
        step('steam', lambda: native_upload(directory, getattr(args, 'steam_api_dll', None)))
    else:
        step('steam', lambda: steam_upload(executable, args.steam_user, directory, config, state['steam_visibility']))
    if config.get('workshop_languages'):
        step('steam_metadata', lambda: publish_metadata(directory / 'workshop-localizations.json',
                                                       getattr(args, 'steam_api_dll', None)))
    if state['audience'] == 'public':
        step('pages', lambda: pages_deploy(config, state['steps']['commit']))
    else:
        step('pages', lambda: 'Private mode: website ZIP attached to private GitHub release; no Pages deployment.')
    step('github_release', lambda: run(['gh', 'release', 'edit', tag, '--repo', repo, '--draft=false',
                                      '--prerelease=' + str(state['audience'] == 'private').lower()]).returncode == 0)
    print(f'Complete: https://github.com/{repo}/releases/tag/{tag}\n'
          f'Steam: https://steamcommunity.com/sharedfiles/filedetails/?id={config["publishedfileid"]}', flush=True)


def native_upload(directory, dll=None):
    command = [sys.executable, ROOT / 'tools/steam_workshop_upload.py', '--directory', directory]
    if dll:
        command += ['--steam-api-dll', dll]
    run(command)
    return True


def publish_metadata(snapshot=None, dll=None):
    command = [sys.executable, ROOT / 'tools/steam_workshop_metadata.py', '--mode', 'publish']
    if snapshot:
        command += ['--snapshot', snapshot]
    if dll:
        command += ['--steam-api-dll', dll]
    run(command)
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['plan', 'prepare', 'publish', 'workshop'], default='plan')
    versions = parser.add_mutually_exclusive_group()
    versions.add_argument('--version')
    versions.add_argument('--bump', choices=['patch', 'minor', 'major'])
    versions.add_argument('--resume', metavar='VERSION')
    parser.add_argument('--audience', choices=['private', 'public'], default='private')
    parser.add_argument('--steam-visibility', choices=['preserve', 'hidden', 'friends', 'unlisted', 'public'], default='preserve')
    parser.add_argument('--steamcmd', default=os.environ.get('STEAMCMD_PATH'))
    parser.add_argument('--steam-backend', choices=['steamcmd', 'native'], default='steamcmd')
    parser.add_argument('--steam-user', default=os.environ.get('STEAM_USER'))
    parser.add_argument('--steam-api-dll', default=os.environ.get('STEAM_API_DLL'))
    parser.add_argument('--notes-file', type=Path)
    args = parser.parse_args(argv)
    with (nullcontext() if args.mode == 'plan' else release_lock(ROOT)):
        execute(args)


def execute(args):
    config = read_json(ROOT / 'tools/release_config.json')
    if args.mode == 'workshop':
        require(not (args.version or args.bump or args.resume or args.notes_file) and args.steam_visibility == 'preserve',
                'Workshop-only mode does not change version, content, notes or visibility.')
        publish_metadata(dll=args.steam_api_dll)
        return
    require(args.audience == 'public' or args.steam_visibility in ('preserve', 'hidden'),
            'Private releases cannot set public/friends/unlisted Steam visibility.')
    if args.resume:
        require(re.fullmatch(r'\d+\.\d+\.\d+', args.resume), 'Invalid resume version.')
        directory = ROOT / 'dist/releases' / args.resume
        state = read_json(directory / 'state.json')
        if args.mode == 'plan':
            print(json.dumps({k: state[k] for k in ('version', 'audience', 'steam_visibility', 'steps')}, ensure_ascii=False, indent=2))
            return
        require(args.mode == 'publish', '--resume is for plan or publish, not prepare.')
        # Stored audience wins; flags cannot silently promote a private snapshot.
        require(args.audience == state['audience'] and args.steam_visibility == state['steam_visibility'],
                'Resume requires the same audience/visibility flags as preparation.')
    else:
        version = next_version(current_version(ROOT), args.version, args.bump)
        notes = args.notes_file.read_text(encoding='utf-8-sig') if args.notes_file else f'织法之杖 v{version}'
        if args.mode == 'plan':
            print(f'PLAN {current_version(ROOT)} -> {version}; {args.audience}; Steam visibility: {args.steam_visibility}\n'
                  f'GitHub: {config["repository"]}; Workshop: {config["publishedfileid"]}\n'
                  'Version -> export -> tests -> ZIPs -> commit/tag/push -> draft GitHub release -> Steam content -> Chinese/English metadata verification -> website -> finish release\n'
                  + ('Website: private downloadable ZIP only.' if args.audience == 'private' else 'Website: public GitHub Pages.')
                  + '\nNo files or remote services were changed. Use --mode prepare or --mode publish.')
            return
        # Fail before version changes if a live publish cannot run.
        if args.mode == 'publish':
            check_audience(args.audience, args.steam_visibility, gh_json('repo', 'view', config['repository'], '--json', 'visibility'))
            if args.steam_backend == 'native':
                require(args.steam_visibility == 'preserve', 'Native upload preserves current Steam visibility.')
                command = [sys.executable, ROOT / 'tools/steam_workshop_metadata.py', '--mode', 'check']
                if args.steam_api_dll:
                    command += ['--steam-api-dll', args.steam_api_dll]
                run(command)
            else:
                executable = args.steamcmd or shutil.which('steamcmd') or shutil.which('steamcmd.exe')
                require(executable and Path(executable).is_file(), 'Publishing requires an installed SteamCMD executable.')
                require(args.steam_user and re.fullmatch(r'[A-Za-z0-9_@.\-]+', args.steam_user),
                        'Supply --steam-user LOGIN (not the display name).')
            if args.audience == 'public':
                pages = gh_json('api', f'repos/{config["repository"]}/pages')
                require(pages.get('build_type') == 'workflow', 'Enable GitHub Pages with source GitHub Actions first.')
        directory, state = prepare(ROOT, config, version, args.audience, args.steam_visibility, notes)
    if args.mode == 'publish':
        publish(directory, state, args)


if __name__ == '__main__':
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError) as error:
        print(f'RELEASE STOPPED: {error}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('Interrupted. Completed stages are retained for --resume.', file=sys.stderr)
        sys.exit(130)
