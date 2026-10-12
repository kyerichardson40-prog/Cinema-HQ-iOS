import hashlib, json, math, re, struct, sys, zipfile, plistlib
from collections import Counter
from pathlib import Path
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

ipa=next(Path(sys.argv[1]).rglob('*.ipa')); out=Path(sys.argv[2]); out.mkdir(parents=True,exist_ok=True)
def save(name,value):
    (out/name).write_text(json.dumps(value,indent=2) if not isinstance(value,str) else value)
def entropy(b):
    return round(-sum((v/len(b))*math.log2(v/len(b)) for v in Counter(b).values()),3) if b else 0
before=hashlib.sha256(ipa.read_bytes()).hexdigest()
with zipfile.ZipFile(ipa) as z:
    info_path=next(n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist',n)); root=info_path.rsplit('/',1)[0]+'/'
    info=plistlib.loads(z.read(info_path)); raw=z.read(root+info['CFBundleExecutable'])
    n=struct.unpack_from('>I',raw,4)[0]; slices=[]
    for i in range(n):
        cpu,sub,off,size,align=struct.unpack_from('>IIIII',raw,8+i*20); slices.append(dict(cpu=cpu,offset=off,size=size))
    arm=next(s for s in slices if s['cpu']==0x100000c); b=raw[arm['offset']:arm['offset']+arm['size']]
    ncmd=struct.unpack_from('<I',b,16)[0]; pos=32; segs=[]; sections=[]; starts=b''; uuid=None; crypt=None
    for _ in range(ncmd):
        cmd,size=struct.unpack_from('<II',b,pos)
        if cmd==0x19:
            name=b[pos+8:pos+24].split(b'\0')[0].decode(); vm,vs,fo,fs=struct.unpack_from('<QQQQ',b,pos+24)
            segs.append(dict(name=name,vm=vm,vmsize=vs,fileoff=fo,filesize=fs))
            for j in range(struct.unpack_from('<I',b,pos+64)[0]):
                p=pos+72+j*80; sn=b[p:p+16].split(b'\0')[0].decode(); addr,sz,offset=struct.unpack_from('<QQI',b,p+32)
                sections.append(dict(name=sn,addr=addr,size=sz,offset=offset))
        if cmd==0x26:
            p,sz=struct.unpack_from('<II',b,pos+8); starts=b[p:p+sz]
        if cmd==0x1b: uuid=b[pos+8:pos+24].hex()
        if cmd==0x2c: crypt=struct.unpack_from('<I',b,pos+16)[0]
        pos+=size
    base=next(s['vm'] for s in segs if s['name']=='__TEXT')
    funcs=[]; acc=base; value=shift=0
    for x in starts:
        value|=(x&127)<<shift
        if x&128: shift+=7;continue
        if not value: break
        acc+=value; funcs.append(acc); value=shift=0
    def fileoff(addr):
        for s in segs:
            if s['vm']<=addr<s['vm']+s['filesize']: return s['fileoff']+addr-s['vm']
        return None
    md=Cs(CS_ARCH_ARM64,CS_MODE_LITTLE_ENDIAN);md.detail=True;md.skipdata=True
    def disasm(start,end):
        p=fileoff(start); return list(md.disasm(b[p:p+end-start],start)) if p is not None else []
    def function(addr):
        import bisect
        idx=bisect.bisect_right(funcs,addr)-1
        return (funcs[idx],funcs[idx+1]) if 0<=idx<len(funcs)-1 else (addr,addr+256)
    (out/'arm64.bin').write_bytes(b)
    (out/'StaticData.json').write_bytes(z.read(root+'data_final/StaticData.json'))
    (out/'Info.plist').write_bytes(z.read(info_path))
    assets=[]
    for leaf in ['file000000.dat','file000000.dat.key','file000002.dat','file000010.dat','file000033.dat','file000039.dat']:
        data=z.read(root+'data_final/'+leaf)
        assets.append(dict(name=leaf,size=len(data),first128=data[:128].hex()))
        (out/(leaf+'.prefix')).write_bytes(data[:262144])
    save('asset_headers.json',assets)
    save('integrity.json',dict(ipa_sha256=before,binary_sha256=hashlib.sha256(raw).hexdigest(),arm64_sha256=hashlib.sha256(b).hexdigest()))
assert hashlib.sha256(ipa.read_bytes()).hexdigest()==before
