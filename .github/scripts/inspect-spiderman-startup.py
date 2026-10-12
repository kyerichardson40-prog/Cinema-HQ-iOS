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
    md=Cs(CS_ARCH_ARM64,CS_MODE_LITTLE_ENDIAN);md.detail=True
    def disasm(start,end):
        p=fileoff(start); return list(md.disasm(b[p:p+end-start],start)) if p is not None else []
    def function(addr):
        import bisect
        idx=bisect.bisect_right(funcs,addr)-1
        return (funcs[idx],funcs[idx+1]) if 0<=idx<len(funcs)-1 else (addr,addr+256)
    terms=['InitialCRMFeed.dat','offline_store','placement_ids','StaticData.json','events.json','player.dat','tuttracking.dat','CRMActionData.dat','ActiveTabIndex','ResetPortalElements','/PortalData/GetStaticData.php','/PortalData/GetEvents.php']
    strings={}; lookup={}
    for s in sections:
        if s['name']!='__cstring': continue
        data=b[s['offset']:s['offset']+s['size']]
        for term in terms:
            for m in re.finditer(re.escape(term.encode()),data):
                begin=data.rfind(b'\0',0,m.start())+1;end=data.find(b'\0',m.start()); addr=s['addr']+begin
                strings.setdefault(term,[]).append(hex(addr-base));lookup[addr]=term
    refs=[]; textsec=next(s for s in sections if s['name']=='__text'); regs={}
    for ins in md.disasm(b[textsec['offset']:textsec['offset']+textsec['size']],textsec['addr']):
        ops=ins.operands
        if ins.mnemonic=='adrp' and len(ops)==2: regs[ops[0].reg]=ops[1].imm
        elif ins.mnemonic=='adr' and len(ops)==2:
            if ops[1].imm in lookup: refs.append(dict(term=lookup[ops[1].imm],pc=hex(ins.address-base),function=hex(function(ins.address)[0]-base)))
        elif ins.mnemonic=='add' and len(ops)==3 and ops[2].type==2:
            addr=regs.get(ops[1].reg,-1)+ops[2].imm
            if addr in lookup:refs.append(dict(term=lookup[addr],pc=hex(ins.address-base),function=hex(function(ins.address)[0]-base)))
            regs.pop(ops[0].reg,None)
        else:
            try:
                for reg in ins.regs_access()[1]: regs.pop(reg,None)
            except Exception:pass
    save('string_references.json',dict(strings=strings,references=refs))
    ranges=[(0x55fc70,0x55fcd0),(0x56465c,0x564930),(0x568e40,0x568eb0),(0x56a13c,0x56a510),(0x56c4f8,0x56c7c0),(0x628e7c,0x629020),(0x6295a8,0x629b60),(0x629b60,0x629ee0)]
    # Include complete functions containing selected data and tutorial references.
    for r in refs:
        if r['term'] in ['tuttracking.dat','player.dat','InitialCRMFeed.dat','offline_store','CRMActionData.dat']:
            start,end=function(base+int(r['pc'],16));ranges.append((start-base,min(end-base,start-base+6000)))
    lines=[]
    for start,end in sorted(set(ranges)):
        lines.append(f'\nRANGE {start:#x}..{end:#x} (image-relative)')
        for i in disasm(base+start,base+end):lines.append(f'{i.address-base:08x} {i.bytes.hex():8s} {i.mnemonic:8s} {i.op_str}')
    save('arm64_paths.txt','\n'.join(lines)+'\n')
    configs=[]; schemas={}
    for n in z.namelist():
        if not n.startswith(root+'data_final/') or n.endswith('/'):continue
        leaf=n.rsplit('/',1)[-1]
        if leaf not in ['InitialCRMFeed.dat','events.json','StaticData.json','QADEBUG.txt','file00000-plantext.dat','FakeIOSBillingData.json']:continue
        data=z.read(n); record=dict(name=leaf,size=len(data),sha256=hashlib.sha256(data).hexdigest(),entropy=entropy(data),first16=data[:16].hex())
        try:
            doc=json.loads(data);record['json']=True
            def schema(v,depth=0):
                if depth>=4:return type(v).__name__
                if isinstance(v,dict):return {k:schema(x,depth+1) for k,x in v.items()}
                if isinstance(v,list):return {'count':len(v),'first_schema':schema(v[0],depth+1) if v else None}
                return type(v).__name__
            schemas[leaf]=schema(doc)
            hits=[]
            def walk(v,path=''):
                if isinstance(v,dict):
                    for k,x in v.items():
                        p=path+'/'+k
                        if re.search(r'portal|recruit|tutorial|offline|placement',k,re.I):hits.append(dict(path=p,type=type(x).__name__,count=len(x) if isinstance(x,(dict,list)) else None))
                        walk(x,p)
                elif isinstance(v,list):
                    for i,x in enumerate(v):walk(x,path+'/'+str(i))
            walk(doc);record['recruitment_keys']=hits[:200]
            if isinstance(doc,dict) and isinstance(doc.get('Version'),str):record['version']=doc['Version']
        except (ValueError,UnicodeError):record['json']=False
        configs.append(record)
        if leaf=='file00000-plantext.dat':save('asset_map.txt',data.decode('utf-8','replace'))
    save('bundled_configuration.json',configs);save('configuration_schema.json',schemas)
    patch=b[0x5648bc:0x5648c0].hex()
    save('integrity.json',dict(ipa_name=ipa.name,ipa_sha256=before,binary_sha256=hashlib.sha256(raw).hexdigest(),arm64_uuid=uuid,cryptid=crypt,patch_at_0x5648bc=patch,segments=segs,static_only=True))
assert hashlib.sha256(ipa.read_bytes()).hexdigest()==before
save('README.txt','Read-only static diagnostics. No game execution, server requests, save edits, or IPA modifications.\nThe input artifact is Portal_Test1, not an untouched original.\nString references and disassembly establish code paths, not whether they executed on the phone.\nNetwork host strings alone do not establish a failed network dependency.\nThe reserve-call NOP is identified at image-relative 0x5648bc.\n')
print('Read-only report generated; source SHA256 unchanged:',before)
