"""Prepare, commit and publish a reviewed code release to Steam, GitHub and Pages.

Public notes require explicit human confirmation. Workshop previews, titles,
descriptions and visibility are never changed by this coordinator.
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


def vdf_quote(value):
    require('\x00' not in str(value), 'NUL is not allowed in VDF.')
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\r', '').replace('\n', '\\n') + '"'


def workshop_changenote(notes):
    """Render standalone Markdown images in release notes for Steam BBCode."""
    return re.sub(r'^!\[([^\]\n]*)\]\((https://[^\s)]+)\)[ \t]*$',
                  lambda m: f'{m[1]}\n[img]{m[2]}[/img]', notes, flags=re.M)


def make_vdf(config, directory, notes):
    require(str(config['publishedfileid']).isdigit() and int(config['publishedfileid']) > 0,
            'An existing Workshop item ID is required. Creating items is intentionally unsupported.')
    values = dict(appid=config['app_id'], publishedfileid=config['publishedfileid'],
                  contentfolder=(directory / 'content').as_posix(), changenote=workshop_changenote(notes))
    # No preview/title/description/visibility keys, even in legacy configurations.
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


def prepare(root, config, version, audience, visibility, notes, commit_notes, notes_approved=False):
    require(notes_approved and notes.strip(), 'Human approval of public notes is required before preparation.')
    require(commit_notes.startswith(f'Release v{version}\n\n') and commit_notes.split('\n\n', 1)[1].strip(),
            'Full commit record must begin with Release vVERSION, a blank line and the complete changes.')
    require(visibility == 'preserve', 'Code releases preserve Workshop visibility.')
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
    package = directory / f'spellwoven-wands-{version}.zip'
    shutil.copy2(checkout / f'dist/nw_weave_dev-{version}.zip', package)
    site_zip = directory / f'field-guide-{version}.zip'
    with zipfile.ZipFile(site_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((checkout / 'site/public').rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(checkout / 'site/public').as_posix())
    (directory / 'notes.txt').write_text(notes, encoding='utf-8')
    (directory / 'commit.txt').write_text(commit_notes, encoding='utf-8')
    (directory / 'workshop.vdf').write_text(make_vdf(config, directory, notes), encoding='utf-8')
    source_paths = read_json(checkout / '.nw_public_export')['files']
    state = dict(release_kind='code', approved_notes_sha256=digest(directory / 'notes.txt'),
                 version=version, audience=audience, steam_visibility=visibility, config=config,
                 checkout=str(checkout), base_commit=git(checkout, 'rev-parse', 'HEAD'), steps={},
                 source_hashes=hashes(checkout, source_paths))
    # SteamCMD rewrites the VDF. Regenerate it from immutable inputs on each retry.
    state['artifact_hashes'] = hashes(directory, [p.relative_to(directory).as_posix()
                                                  for p in directory.rglob('*') if p.is_file() and p.name != 'workshop.vdf'])
    save(directory / 'state.json', state)
    print(f'Prepared {version}: {directory}. No commit, push or upload has run.', flush=True)
    return directory, state


def steam_upload(executable, username, directory, config, visibility):
    require(visibility == 'preserve', 'Code releases preserve Workshop visibility.')
    require(executable and Path(executable).is_file(), 'Supply --steamcmd PATH or install steamcmd on PATH.')
    require(username and re.fullmatch(r'[A-Za-z0-9_@.\-]+', username), 'Supply --steam-user (login name, not display name).')
    log = Path(executable).resolve().parent / 'logs/workshop_log.txt'
    offset = log.stat().st_size if log.exists() else 0
    (directory / 'workshop.vdf').write_text(make_vdf(config, directory,
        (directory / 'notes.txt').read_text(encoding='utf-8')), encoding='utf-8')
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


def validate_release(directory, state):
    require(state.get('release_kind') == 'code',
            'Legacy snapshots are not code-only releases; do not resume them with this coordinator.')
    require(state['steam_visibility'] == 'preserve', 'Code releases preserve Workshop visibility.')
    require(state.get('approved_notes_sha256') == digest(directory / 'notes.txt'),
            'Approved public notes changed or approval is missing.')
    config, checkout = state['config'], Path(state['checkout'])
    validate_checkout(checkout, config)
    verify_hashes(checkout, state['source_hashes'])
    verify_hashes(directory, state['artifact_hashes'])
    content_files = {p.relative_to(directory).as_posix() for p in (directory / 'content').rglob('*') if p.is_file()}
    require(content_files == {p for p in state['artifact_hashes'] if p.startswith('content/')},
            'Unexpected files in the frozen Steam content directory.')
    source_files = {p for p in git(checkout, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split('\0')
                    if p and (checkout / p).is_file()}
    require(source_files == set(state['source_hashes']), 'Unexpected source files in the release checkout.')


def commit_release(directory, state):
    validate_release(directory, state)
    checkout = Path(state['checkout'])
    expected = (directory / 'commit.txt').read_text(encoding='utf-8').strip()
    head = git(checkout, 'rev-parse', 'HEAD')
    if head == state['base_commit']:
        require('commit' not in state['steps'], 'Previously committed checkout was moved backwards.')
        git(checkout, 'add', '--all')
        git(checkout, 'commit', '--cleanup=verbatim', '--file', str(directory / 'commit.txt'))
    else:
        require(git(checkout, 'log', '-1', '--format=%B') == expected
                and git(checkout, 'rev-parse', 'HEAD^') == state['base_commit'],
                'Checkout advanced outside this release or full commit record differs.')
    require(git(checkout, 'log', '-1', '--format=%B') == expected, 'Commit message differs from the full frozen record.')
    require(not git(checkout, 'status', '--porcelain'), 'Uncommitted files remain after release commit.')
    head = git(checkout, 'rev-parse', 'HEAD')
    require(state['steps'].get('commit', head) == head, 'Recorded release commit differs.')
    state['steps']['commit'] = head
    save(directory / 'state.json', state)
    print(f'Committed {head}. Nothing pushed or uploaded.', flush=True)


def publish(directory, state, args):
    validate_release(directory, state)
    require(state['steps'].get('commit'), 'Commit the prepared release with --mode commit before publishing.')
    config, checkout = state['config'], Path(state['checkout'])
    repo, version = config['repository'], state['version']
    state_path = directory / 'state.json'
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


@contextmanager
def github_auth():
    """Use normal gh auth, or the existing Git credential for github.com in memory."""
    if os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN'):
        yield
        return
    status = subprocess.run(['gh', 'auth', 'status'], capture_output=True)
    if status.returncode == 0:
        yield
        return
    env = dict(os.environ, GCM_INTERACTIVE='Never', GIT_TERMINAL_PROMPT='0')
    result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                            text=True, capture_output=True, env=env)
    fields = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    require(result.returncode == 0 and fields.get('password'),
            'GitHub authentication unavailable. Run gh auth login, then retry.')
    os.environ['GH_TOKEN'] = fields['password']
    try:
        yield
    finally:
        os.environ.pop('GH_TOKEN', None)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['plan', 'prepare', 'commit', 'publish'], default='plan')
    versions = parser.add_mutually_exclusive_group()
    versions.add_argument('--version')
    versions.add_argument('--bump', choices=['patch', 'minor', 'major'])
    versions.add_argument('--resume', metavar='VERSION')
    parser.add_argument('--audience', choices=['private', 'public'], default='private')
    parser.add_argument('--steam-backend', choices=['steamcmd', 'native'], default='native')
    parser.add_argument('--steamcmd', default=os.environ.get('STEAMCMD_PATH'))
    parser.add_argument('--steam-user', default=os.environ.get('STEAM_USER'))
    parser.add_argument('--steam-api-dll', default=os.environ.get('STEAM_API_DLL'))
    parser.add_argument('--notes-file', type=Path)
    parser.add_argument('--commit-file', type=Path)
    parser.add_argument('--notes-approved', action='store_true',
                        help='Only set after the user explicitly approves the public notes in this release.')
    args = parser.parse_args(argv)
    with (nullcontext() if args.mode == 'plan' else release_lock(ROOT)):
        execute(args)


def execute(args):
    config = read_json(ROOT / 'tools/release_config.json')
    if args.resume:
        require(re.fullmatch(r'\d+\.\d+\.\d+', args.resume), 'Invalid resume version.')
        require(args.mode in ('plan', 'commit', 'publish'), '--resume is for plan, commit or publish.')
        require(not (args.notes_file or args.commit_file or args.notes_approved),
                'Resume uses frozen notes and approval; do not supply replacements.')
        directory = ROOT / 'dist/releases' / args.resume
        state = read_json(directory / 'state.json')
        if args.mode == 'plan':
            print(json.dumps({k: state[k] for k in ('version', 'audience', 'steps')}, ensure_ascii=False, indent=2))
            return
        require(args.audience == state['audience'], 'Resume requires the same audience as preparation.')
        if args.mode == 'commit':
            commit_release(directory, state)
        else:
            with github_auth():
                publish(directory, state, args)
        return
    require(args.mode in ('plan', 'prepare'), 'Commit/publish requires --resume VERSION after preparation.')
    version = next_version(current_version(ROOT), args.version, args.bump)
    if args.mode == 'plan':
        print(f'PLAN {current_version(ROOT)} -> {version}; {args.audience}\n'
              'Review complete changes -> user approves public notes -> prepare version/files/tests -> commit full record -> publish\n'
              'Publish: Git push/tag + GitHub Release + Steam content/changenote/version tag + Pages (public only).\n'
              'Workshop preview, title, description and visibility are preserved. No files or services changed.')
        return
    require(args.notes_approved and args.notes_file and args.commit_file,
            'After human confirmation, supply --notes-approved, --notes-file and --commit-file.')
    notes = args.notes_file.read_text(encoding='utf-8-sig')
    commit_notes = args.commit_file.read_text(encoding='utf-8-sig')
    with github_auth():
        check_audience(args.audience, 'preserve', gh_json('repo', 'view', config['repository'], '--json', 'visibility'))
        prepare(ROOT, config, version, args.audience, 'preserve', notes, commit_notes, notes_approved=True)


if __name__ == '__main__':
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError) as error:
        print(f'RELEASE STOPPED: {error}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('Interrupted. Completed stages are retained for --resume.', file=sys.stderr)
        sys.exit(130)
