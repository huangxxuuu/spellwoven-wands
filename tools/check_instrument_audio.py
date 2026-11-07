"""Verify all instrument mappings; optionally load/play the bank using DST's FMOD DLLs."""
import argparse
import ctypes as c
import hashlib
import json
import os
import struct
import time
import wave
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def check(game=None):
    source = ROOT / 'assets_src/audio/instruments'
    notes = [n for group in json.loads((source / 'events.json').read_text())['instruments'].values() for n in group]
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + lua.globals().package.path
    arsenal = lua.eval('require("nw/arsenal")')
    samples = lua.eval('require("nw/instrument_samples")')
    for note in notes:
        instrument = note['event'].split('/')[1]
        sample = samples[instrument]['samples'][note['midi'] - 48]
        assert sample['event'] == note['event']
        assert abs(sample['duration'] - note['duration']) < .000001
        assert hashlib.sha256((source / note['file']).read_bytes()).hexdigest() == note['sha256']
    for card, base in arsenal['notes'].items():
        bank = samples[base['instrument']]
        for target in range(bank['min'] - 1, bank['max'] + 2):
            tone = arsenal['resolve_tone'](card, target - base['pitch'])
            assert tone['pitch'] == target
            assert tone['supported'] == (bank['min'] <= target <= bank['max'])
            if tone['supported']:
                assert tone['event'] == 'nw_instruments/%s/m%03d' % (base['instrument'], target + 48)
    for language in ('zh', 'en'):
        lua.eval('require("nw/locale").configure')(language, language)
        for card, base in arsenal['notes'].items():
            text = lua.eval('require("nw/spell_briefs").get')(card)
            assert samples[base['instrument']]['range'] in text
            assert ('playable range' if language == 'en' else '可调音域') in text
    print('PASS: 76 source hashes, event mappings/durations, 14 cards across all notes/bounds, bilingual tooltips')
    if game is None:
        return
    with os.add_dll_directory(str(game / 'bin64')):
        low = c.WinDLL(str(game / 'bin64/fmodex64.dll'))
        event = c.WinDLL(str(game / 'bin64/fmod_event64.dll'))

        def call(lib, name, *args):
            code = getattr(lib, name)(*args)
            if code:
                raise RuntimeError(f'{name}: FMOD error {code}')

        def verify_pcm(sound, note):
            length = c.c_uint()
            call(low, 'FMOD_Sound_GetLength', sound, c.byref(length), 4)
            with wave.open(str(source / note['file'])) as wav:
                expected = wav.readframes(wav.getnframes())
            assert length.value == len(expected), note['event']
            a, b, na, nb = c.c_void_p(), c.c_void_p(), c.c_uint(), c.c_uint()
            call(low, 'FMOD_Sound_Lock', sound, 0, length, c.byref(a), c.byref(b), c.byref(na), c.byref(nb))
            try:
                pcm = c.string_at(a, na.value) + (c.string_at(b, nb.value) if nb.value else b'')
                assert pcm == expected, note['event']
            finally:
                call(low, 'FMOD_Sound_Unlock', sound, a, b, na, nb)
            return length.value // 2  # Mono PCM16 frames.

        system = c.c_void_p()
        call(event, 'FMOD_EventSystem_Create', c.byref(system))
        try:
            core = c.c_void_p()
            call(event, 'FMOD_EventSystem_GetSystemObject', system, c.byref(core))
            call(low, 'FMOD_System_SetOutput', core, 2)  # NOSOUND; no game or speakers needed.
            call(event, 'FMOD_EventSystem_Init', system, 128, 0, None, 0)
            media = str(ROOT / 'mod/sound') + '/'
            call(event, 'FMOD_EventSystem_SetMediaPath', system, media.encode())
            project = c.c_void_p()
            call(event, 'FMOD_EventSystem_Load', system, b'nw_instruments.fev', None, c.byref(project))
            instances = []
            for note in notes:
                instance = c.c_void_p()
                call(event, 'FMOD_EventSystem_GetEvent', system, note['event'].encode(), 0, c.byref(instance))
                call(event, 'FMOD_Event_Start', instance)
                call(event, 'FMOD_EventSystem_Update', system)
                group = c.c_void_p()
                call(event, 'FMOD_Event_GetChannelGroup', instance, c.byref(group))
                channels = c.c_int()
                call(low, 'FMOD_ChannelGroup_GetNumChannels', group, c.byref(channels))
                assert channels.value == 1, note['event']
                channel = c.c_void_p()
                call(low, 'FMOD_ChannelGroup_GetChannel', group, 0, c.byref(channel))
                repeats = c.c_int()
                call(low, 'FMOD_Channel_GetLoopCount', channel, c.byref(repeats))
                assert repeats.value == 0, (note['event'], 'sample repeats', repeats.value)
                frequency = c.c_float()
                call(low, 'FMOD_Channel_GetFrequency', channel, c.byref(frequency))
                assert frequency.value == 44100, note['event']
                current = c.c_void_p()
                call(low, 'FMOD_Channel_GetCurrentSound', channel, c.byref(current))
                frames = verify_pcm(current, note)
                # Seek to the tail and let FMOD end it itself; never force Stop.
                call(low, 'FMOD_Channel_SetPosition', channel, frames - 256, 2)
                instances.append((instance, note['event']))
            time.sleep(.2)
            call(event, 'FMOD_EventSystem_Update', system)
            for instance, name in instances:
                state = c.c_int()
                call(event, 'FMOD_Event_GetState', instance, c.byref(state))
                assert not state.value & 16, (name, 'still playing after sample end', state.value)
            sound = c.c_void_p()
            call(low, 'FMOD_System_CreateSound', core, (media + 'nw_instruments.fsb').encode(), 0, None, c.byref(sound))
            count = c.c_int()
            call(low, 'FMOD_Sound_GetNumSubSounds', sound, c.byref(count))
            assert count.value == len(notes)
            by_name = {Path(n['file']).stem: n for n in notes}
            # FMOD's sample API can omit names. Read the FSB5 v1 name table instead.
            fsb = (ROOT / 'mod/sound/nw_instruments.fsb').read_bytes()
            magic, version, sample_count, header_size, names_size = struct.unpack_from('<4s4I', fsb)
            assert (magic, version, sample_count) == (b'FSB5', 1, len(notes))
            names = fsb[60 + header_size:60 + header_size + names_size]
            checked = set()
            for index in range(count.value):
                sub = c.c_void_p()
                call(low, 'FMOD_Sound_GetSubSound', sound, index, c.byref(sub))
                offset = struct.unpack_from('<I', names, index * 4)[0]
                key = Path(names[offset:].split(b'\0', 1)[0].decode()).stem
                note = by_name[key]
                verify_pcm(sub, note)
                checked.add(key)
            assert len(checked) == len(notes)
            call(low, 'FMOD_Sound_Release', sound)
            print('PASS: 76 native events each play exactly their matching single-note WAV once, at original pitch, and end automatically; bank PCM matches all sources')
        finally:
            call(event, 'FMOD_EventSystem_Release', system)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, help='DST installation for optional native FMOD validation (Windows x64)')
    check(parser.parse_args().game)
