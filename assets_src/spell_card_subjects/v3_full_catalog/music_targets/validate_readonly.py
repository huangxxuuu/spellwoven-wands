from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image
base=Path(r"D:/Projects/AI/dst_mod/assets_src/spell_card_subjects/v3_full_catalog/music_targets")
checks=[]
for jf in sorted(base.glob("*.result.json")):
    result=json.loads(jf.read_text(encoding="utf-8-sig"))
    if result.get("status")!="generated": continue
    p=Path(result["output"])
    with Image.open(p) as im:
        im.load()
        mode=im.mode; size=im.size
        a=np.asarray(im.convert("RGBA"))
    alpha=a[:,:,3]; rgb=a[:,:,:3].astype(int)
    box={}
    for threshold in (1,8,32,128,250):
        y,x=np.nonzero(alpha>=threshold)
        box[str(threshold)]=[int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1)] if len(x) else None
    red=(rgb[:,:,0]>200)&(rgb[:,:,1]<80)&(rgb[:,:,2]<80)
    green=(rgb[:,:,1]>180)&(rgb[:,:,0]<90)&(rgb[:,:,2]<90)
    border=np.concatenate([alpha[0,:],alpha[-1,:],alpha[:,0],alpha[:,-1]])
    source=Path(result["source"])
    digest=hashlib.sha256(p.read_bytes()).hexdigest()
    checks.append({
        "id":result["id"],"mode":mode,"size":size,
        "sha256":digest,"matches_original":digest==hashlib.sha256(source.read_bytes()).hexdigest(),
        "transparent_pixels":int((alpha==0).sum()),"opaque_pixels":int((alpha==255).sum()),
        "nearly_opaque_pixels":int((alpha>=250).sum()),"alpha_bboxes":box,
        "border_pixels_alpha_gte8":int((border>=8).sum()),
        "red_pixels_alpha_gte8":int((red&(alpha>=8)).sum()),
        "green_pixels_alpha_gte8":int((green&(alpha>=8)).sum()),
        "red_pixels_alpha_1_to_7":int((red&(alpha>0)&(alpha<8)).sum()),
        "green_pixels_alpha_1_to_7":int((green&(alpha>0)&(alpha<8)).sum())
    })
payload={"method":"Read-only PNG decode, RGBA/alpha and bounding-box inspection; SHA256 equality with original. Saturated color counts are diagnostics, not automatic defects; red is intentional for some subjects. No image pixels were modified.","count":len(checks),"assets":checks}
(base/"validation.json").write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps({"count":len(checks),"all_rgba":all(c["mode"]=="RGBA" for c in checks),"all_copies_identical":all(c["matches_original"] for c in checks),"all_true_transparent":all(c["transparent_pixels"]>0 and c["nearly_opaque_pixels"]>0 for c in checks),"touching_canvas_at_alpha8":[c["id"] for c in checks if c["border_pixels_alpha_gte8"]>0]},ensure_ascii=False))

