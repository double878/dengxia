"""Read-only audit of the current vocal-only and reference-puppet revision."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import numpy as np
from PIL import Image


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def pcm(path):
    with wave.open(str(path),"rb") as src:
        assert src.getparams()[:3]==(2,2,48000),path
        return src.readframes(src.getnframes())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--batch",type=Path,required=True)
    parser.add_argument("--ffmpeg",type=Path,required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    audio=root/"assets/audio"; art=root/"assets/puppets"
    batch=args.batch.resolve();before=batch/"before"
    manifest=load(audio/"original-audio-sources.json")
    previous=load(before/"audio/original-audio-sources.json")
    assert manifest["duet_accompaniment_enabled"] is False
    changed=[];unchanged=0
    for rel,expected in manifest["outputs"].items():
        path=audio/rel
        assert sha(path)==expected,rel
        if path.suffix==".wav":
            data=pcm(path)
            assert len(data)>0
            subprocess.run([str(args.ffmpeg),"-nostdin","-v","error","-xerror","-i",str(path),"-f","null","-"],check=True,capture_output=True,timeout=60)
            if sha(path)==sha(before/"audio"/rel):unchanged+=1
            else:changed.append(rel)
    assert set(changed)=={"act1-natural/main.wav","act2-hall/main.wav","act2-hall/wine-duet.wav"}
    for folder,key in [("act1-natural","act1"),("act2-hall","act2-hall")]:
        data=pcm(audio/folder/"main.wav")
        old=pcm(before/"audio"/folder/"main.wav")
        region=previous["replaced_regions"][key][0]
        start,end=region["start_frame"]*4,region["end_frame"]*4
        assert len(data)==len(old) and data[:start]==old[:start] and data[end:]==old[end:]
        current=manifest["music"]["act1-duet" if key=="act1" else "act2-duet"]
        assert hashlib.sha256(data[start:end]).hexdigest()==current["pcm_sha256"]
        assert sha(audio/folder/"main.wav")==manifest["baseline"][folder+"/main.wav"],folder
        assert load(audio/folder/"score.json")["background_music"] is False
    assert load(audio/"act2-opening/score.json")["background_music"] is True
    now=load(art/"puppet_assets.json");old=load(before/"puppets/puppet_assets.json")
    report=load(art/"reference-revision.json")
    for name,digest in report["outputs"].items():assert sha(art/name)==digest,name
    for name,digest in manifest["tools"].items():assert sha(root/"tools"/name)==digest,name
    assert sha(root/"tools/prepare_couple_references.py")==report["tool_sha256"]
    for name in now["characters"]:
        if name not in ["xuxian","baisuzhen","fahai"]:
            assert now["characters"][name]==old["characters"][name],name
    previous_fahai=old["characters"]["fahai"].copy()
    current_fahai=copy.deepcopy(now["characters"]["fahai"])
    assert 1.38<current_fahai.pop("staff_rotation_rad")<1.4
    assert current_fahai.pop("staff_down_length_ratio")==1.1
    extension=current_fahai["parts"].pop("staff_extension")
    assert extension["rect"]==[1024,1536,512,512]
    assert current_fahai==previous_fahai
    old_fahai=np.asarray(Image.open(before/"puppets/fahai.png"))
    new_fahai=np.asarray(Image.open(art/"fahai.png"))
    assert np.array_equal(old_fahai[:1536],new_fahai[:1536])
    assert np.array_equal(old_fahai[1536:,:1024],new_fahai[1536:,:1024])
    assert np.array_equal(old_fahai[1536:,1536:],new_fahai[1536:,1536:])
    assert (new_fahai[1600:2026,1272:1288,3]>127).sum()>1000
    for name in ["xuxian","baisuzhen"]:
        skin=now["characters"][name]
        assert skin["reference_facing"]==old["characters"][name]["reference_facing"]
        if name=="baisuzhen":
            assert skin["shoulder_half_width_ratio"]==old["characters"][name]["shoulder_half_width_ratio"]
        else:
            assert skin["shoulder_half_width_ratio"]==.055
        assert "lower_body" in skin["parts"]
        for field in ["neck_attachment_ratio","head_neck_offset_ratio"]:
            assert len(skin[field])==2 and np.isfinite(skin[field]).all(),(name,field)
        ref=art/skin["reference"]["filename"]
        assert sha(ref)==skin["reference"]["sha256"]
        assert Image.open(ref).size==(1280,2278)
        atlas=Image.open(art/(name+".png"))
        assert atlas.mode=="RGBA" and atlas.size==(2048,2048)
        for part,row in skin["parts"].items():
            if part in old["characters"][name]["parts"]:
                assert row["pivot"]==old["characters"][name]["parts"][part]["pivot"],(name,part)
                assert row["rect"]==old["characters"][name]["parts"][part]["rect"]
            x,y,w,h=row["rect"]
            alpha=np.asarray(atlas.crop((x,y,x+w,y+h)))[:,:,3]
            assert (alpha>127).sum()>50,(name,part)
            assert not alpha[:4].any() and not alpha[-4:].any() and not alpha[:,:4].any() and not alpha[:,-4:].any(),(name,part)
        # No stage floor, Doubao attribution, pole tail or basket is extracted.
        cutout=Image.open(batch/name/"cutout.png")
        assert cutout.getchannel("A").getbbox()[3]<1900
        bounds=cutout.getbbox();natural_height=bounds[3]-bounds[1]
        scale=512/(skin["head_size_per_radius"]*.105*natural_height)
        head=skin["parts"]["head"]
        neck=skin["reference"]["neck_insertion_xy"]
        origin=head["reference_axis"][0]
        mirror=skin["reference"]["canonical_mirror_x"]
        point=tuple(round(head["pivot"][i]+(neck[i]-origin[i])*scale*(mirror if i==0 else 1)) for i in range(2))
        assert atlas.getpixel(point)[3]>200,(name,"neck source must survive cutout")
        if name=="xuxian":
            assert not np.asarray(cutout.getchannel("A"))[1160:1350,830:1100].any()
    result=dict(passed=True,audio_decoded=unchanged+len(changed),unchanged_wavs=unchanged,
        exact_clean_vocal_masters=2,only_duet_pcm_changed=True,opening_and_fahai_unchanged=True,
        new_couple_parts=[len(now["characters"][n]["parts"]) for n in ["baisuzhen","xuxian"]],
        original_rects_and_pivots=True,other_characters_unchanged=True)
    result.update(neck_source_preserved=True,original_fahai_tiles_unchanged=True,staff_extended_downward=True)
    (batch/"audit.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result))


if __name__=="__main__":main()
