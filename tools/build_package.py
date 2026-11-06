"""Package only the installable mod and a standalone test guide."""
import hashlib
import json
import re
import zipfile
from pathlib import Path

root=Path(__file__).resolve().parents[1]
version=re.search(r'^version\s*=\s*"([^"]+)"',(root/"mod/modinfo.lua").read_text(encoding="utf-8"),re.MULTILINE).group(1)
out=root/f"dist/nw_weave_dev-{version}.zip"
out.parent.mkdir(exist_ok=True)
hashes={}
with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:
    for path in sorted((root/"mod").rglob("*")):
        if path.is_file():
            name="nw_weave_dev/"+path.relative_to(root/"mod").as_posix()
            data=path.read_bytes()
            z.writestr(name,data)
            hashes[name]=hashlib.sha256(data).hexdigest()
    z.write(root/"docs/11_法术卡测试指南.md","TEST_GUIDE.md")
    z.write(root/"docs/07_法术说明与参数.md","07_法术说明与参数.md")
    z.write(root/"docs/04_开发执行规格.md","04_开发执行规格.md")
    z.write(root/"docs/09_获取系统实机验收.md","CRAFT_TEST_GUIDE.md")
    z.write(root/"docs/05_首轮人工测试.md","CAST_TEST_GUIDE.md")
    z.writestr("SHA256.json",json.dumps(hashes,indent=2))
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
    for name,digest in hashes.items():
        assert hashlib.sha256(z.read(name)).hexdigest()==digest
print("PASS",out,len(hashes),"mod files",out.stat().st_size,"bytes")
