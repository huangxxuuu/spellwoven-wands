"""Bounded player journal: actual DST save serialization and Lua 5.1 microbenchmark."""
import argparse
import json
import time
import zipfile
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--game', type=Path, default=Path("E:/SteamLibrary/steamapps/common/Don't Starve Together"))
args = parser.parse_args()
vm = LuaRuntime(unpack_returned_tuples=True)
vm.globals().package.path = str(ROOT / 'mod/scripts/?.lua').replace('\\', '/') + ';' + vm.globals().package.path
vm.execute('''
Class=function(fn)
    local c={};c.__index=c
    return setmetatable(c,{__call=function(_,...) local s=setmetatable({},c);fn(s,...);return s end})
end
GetTime=function() return 0 end
EQUIPSLOTS={HANDS='hands'}
TheWorld={state={cycles=99,time=.5}}
TheShard={GetShardId=function() return '1' end}
''')
with zipfile.ZipFile(args.game / 'data/databundles/scripts.zip') as archive:
    vm.execute(archive.read('scripts/dumper.lua').decode())
vm.execute('''
local Journal=require('components/nw_spelljournal')
local held
journal=Journal({components={inventory={GetEquippedItem=function() return held end}}})
for _,id in ipairs(require('nw/cards').order) do
    journal:Collect(id)
    journal:RecordCast({cards={{card_uid='sample',spell_id=id}}},{trace={{event='execute',card='sample'}}})
    journal.cards[id].casts=1000000
    journal:RecordDamage(id,12345678.125,0)
end
local n=0
for metric,direction in pairs(Journal.metrics) do for rank=1,3 do
    n=n+1
    local d=require('nw/generator').starter()
    d.wand_uid='nw:ABCDEF0123456789:1:'..n
    d.source='test-boss-source';d.archetype='reservoir';d.tier=4
    d.stats.capacity=12;d.cards={}
    d.stats[metric]=direction==1 and 10000-rank or -10000+rank
    if metric=='capacity' then d.stats.capacity=13-rank end
    for i=1,12 do d.cards[i]={spell_id='edge_spear_wathgrithr_lightning_charged'} end
    held={components={nw_wand={data=d},named={name=string.rep('星',32)}},HasTag=function() return true end}
    journal:ObserveWand(held)
end end
journal:RecordDamage('spark',1e10,1000)
''')
serialized = vm.eval('DataDumper(journal:OnSave(),nil,true)')
bench = vm.eval('function(n) for i=1,n do journal:RecordDamage("spark",1,i/3000) end end')
started = time.perf_counter()
bench(100000)
elapsed = time.perf_counter() - started
count = vm.eval('function(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end')
runtime_buckets = count(vm.globals().journal._buckets)
record_bench = vm.eval('''function(n)
    for i=1,n do
        journal.max_hit=0;journal.best_damage={}
        journal:RecordDamage("spark",1,1000+i/3000)
    end
end''')
started = time.perf_counter()
record_bench(10000)
record_elapsed = time.perf_counter() - started
result = {
    'cards': count(vm.globals().journal.cards),
    'wand_snapshots': count(vm.globals().journal.wands),
    'engine_serialized_bytes': len(serialized.encode()),
    'damage_events': 100000,
    'seconds_lua51_host': elapsed,
    'microseconds_per_damage_event': elapsed * 1e6 / 100000,
    'microseconds_per_record_with_wand': record_elapsed * 1e6 / 10000,
    'runtime_buckets': runtime_buckets,
}
report = ROOT / 'test_reports/spelljournal_size_perf.json'
report.parent.mkdir(exist_ok=True)
report.write_text(json.dumps(result, indent=2), encoding='utf8')
print(json.dumps(result, indent=2))
