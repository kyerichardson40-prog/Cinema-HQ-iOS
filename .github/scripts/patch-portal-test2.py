"""Test2: renew baseline portal dates in the bundled feed; retain Test1 binary."""
import copy
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path

KEY=(1765,53919,1,0)
DELTA=0x9e3779b9
MASK=0xffffffff
INPUT_BINARY_SHA='7da6f8b352e2f2803b615e6999c846a640f8f0784cee4ac454703818431e18d2'
FEED='Payload/Spiderman.app/data_final/InitialCRMFeed.dat'
BINARY='Payload/Spiderman.app/Spiderman'
END_DATE='2040-12-31'

def transform(data, decrypt=False):
    assert len(data)%4==0 and len(data)>=8
    v=list(struct.unpack('<%dI'%(len(data)//4),data)); n=len(v); rounds=6+52//n
    def mx(z,y,total,p,e):
        return ((((z>>5)^(y<<2))+((y>>3)^(z<<4)))^((total^y)+(KEY[(p&3)^e]^z)))&MASK
    if decrypt:
        total=(rounds*DELTA)&MASK; y=v[0]
        while total:
            e=(total>>2)&3
            for p in range(n-1,0,-1):
                z=v[p-1];v[p]=(v[p]-mx(z,y,total,p,e))&MASK;y=v[p]
            z=v[-1];v[0]=(v[0]-mx(z,y,total,0,e))&MASK;y=v[0];total=(total-DELTA)&MASK
    else:
        total=0;z=v[-1]
        for _ in range(rounds):
            total=(total+DELTA)&MASK;e=(total>>2)&3
            for p in range(n-1):
                y=v[p+1];v[p]=(v[p]+mx(z,y,total,p,e))&MASK;z=v[p]
            y=v[0];v[-1]=(v[-1]+mx(z,y,total,n-1,e))&MASK;z=v[-1]
    return struct.pack('<%dI'%n,*v)

def unpack_feed(data):
    plain=transform(data,True);n=struct.unpack_from('<I',plain)[0]
    assert 0<n<=len(plain)-36
    assert plain[4+n:36+n]==hashlib.md5(plain[:4+n]).hexdigest().upper().encode()
    assert not any(plain[36+n:])
    return json.loads(plain[4:4+n]),plain

def patch_feed(data):
    original,plain=unpack_feed(data)
    assert transform(plain)==data,'Original codec round-trip must be exact'
    patched=copy.deepcopy(original);changes=[]
    for category,portals in patched['game']['LiveOps']['Portals'].items():
        for p in portals:
            if category in ('Standard','Premium') or p['Id'] in ('special_gacha_01','vip_gacha'):
                changes.append({'category':category,'id':p['Id'],'old_end_date':p['EndDate'],'new_end_date':END_DATE})
                p['EndDate']=END_DATE
    assert len(changes)==36,len(changes)
    # Prove that only the selected EndDate fields have changed semantically.
    restored=copy.deepcopy(patched)
    for c in changes:
        matches=[p for p in restored['game']['LiveOps']['Portals'][c['category']] if p['Id']==c['id']]
        assert len(matches)==1;matches[0]['EndDate']=c['old_end_date']
    assert restored==original
    payload=json.dumps(patched,separators=(',',':'),ensure_ascii=True).encode()
    newplain=struct.pack('<I',len(payload))+payload
    newplain+=hashlib.md5(newplain).hexdigest().upper().encode()
    newplain+=b'\0'*((-len(newplain))%4)
    encrypted=transform(newplain)
    checked,_=unpack_feed(encrypted);assert checked==patched
    return encrypted,changes

def main():
    source,output,report=map(Path,sys.argv[1:4]);source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    with zipfile.ZipFile(source) as z:
        assert hashlib.sha256(z.read(BINARY)).hexdigest()==INPUT_BINARY_SHA,'Wrong input: expected Portal Test1'
        newfeed,changes=patch_feed(z.read(FEED))
        with zipfile.ZipFile(output,'w') as dest:
            for entry in z.infolist():
                dest.writestr(entry,newfeed if entry.filename==FEED else z.read(entry.filename))
        with zipfile.ZipFile(output) as dest:
            assert dest.testzip() is None
            assert set(z.namelist())==set(dest.namelist())
            for entry in z.infolist():
                if entry.filename!=FEED:
                    other=dest.getinfo(entry.filename);assert (entry.CRC,entry.file_size)==(other.CRC,other.file_size)
            assert hashlib.sha256(dest.read(BINARY)).hexdigest()==INPUT_BINARY_SHA
            checked,_=unpack_feed(dest.read(FEED));assert len(changes)==36
    assert hashlib.sha256(source.read_bytes()).hexdigest()==source_hash
    report.mkdir(parents=True,exist_ok=True)
    (report/'patch_report.json').write_text(json.dumps({'test':'Portal Test2 date renewal','input_sha256':source_hash,'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'binary_unchanged':True,'save_files_modified':False,'changed_entry':FEED,'changes':changes,'verified':['original encryption round-trip','new feed checksum and decryption','only 36 EndDate values changed','all other archive entries unchanged','ZIP integrity'],'runtime_verified':False},indent=2))
    print('Test2 verified:',len(changes),'portal dates renewed. Output:',output)

if __name__=='__main__':main()
