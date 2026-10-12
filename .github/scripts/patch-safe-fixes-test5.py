"""Test5: bounded portal selection, populated catalogues and bundled texture fallback."""
import copy,hashlib,importlib.util,io,json,struct,sys,zipfile,zlib
from pathlib import Path

SOURCE_SHA='a290559f906111e98b312e2c7f6d176262b1665edb44e076fd5c93bc2beaa523'
BINARY_SHA='bc44bd9ce801085454eb1e79d5e5b41a57b9eae3757afc578bcefccb3b341d5b'
ROOT='Payload/Spiderman.app/'
BINARY=ROOT+'Spiderman'; FEED=ROOT+'data_final/InitialCRMFeed.dat'
def sha(data): return hashlib.sha256(data).hexdigest()
def read(arc,name):
    try: return arc.read(name)
    except zipfile.BadZipFile:
        info=arc.getinfo(name);f=arc.fp;f.seek(info.header_offset);h=f.read(30)
        assert h[:4] in (b'PK\x03\x04',b'QM\x06\x08')
        a,b=struct.unpack_from('<HH',h,26);f.seek(a+b,1);data=f.read(info.compress_size)
        if info.compress_type==8: data=zlib.decompress(data,-15)
        else: assert info.compress_type==0
        assert len(data)==info.file_size and zlib.crc32(data)&0xffffffff==info.CRC
        return data

def patch_binary(data):
    assert sha(data)==BINARY_SHA
    slices=[struct.unpack_from('>IIIII',data,8+i*20) for i in range(struct.unpack_from('>I',data,4)[0])]
    arm=next(s for s in slices if s[0]==0x100000c);off,size=arm[2:4]
    site,cave=0x56467c,0x2000
    assert data[off+site:off+site+4]==bytes.fromhex('f50301aa')
    # The cave must be after load commands and before every file-backed section.
    ncmds,sizeofcmds=struct.unpack_from('<II',data,off+16)
    assert 32+sizeofcmds<=cave
    cursor=off+32;section_ranges=[]
    for _ in range(ncmds):
        cmd,length=struct.unpack_from('<II',data,cursor)
        if cmd==0x19:
            count=struct.unpack_from('<I',data,cursor+64)[0]
            for j in range(count):
                sec=cursor+72+80*j
                length_sec=struct.unpack_from('<Q',data,sec+40)[0]
                fileoff,flags=struct.unpack_from('<I',data,sec+48)[0],struct.unpack_from('<I',data,sec+64)[0]
                if fileoff and (flags&255) not in (1,12,18): section_ranges.append((fileoff,fileoff+length_sec))
        cursor+=length
    assert cursor==off+32+sizeofcmds
    assert section_ranges and min(a for a,b in section_ranges)>=cave+16
    assert data[off+cave:off+cave+16]==bytes(16)
    # x30 is saved by this function's existing prologue before the new BL.
    assert data[off+0x564670:off+0x564674]==bytes.fromhex('fd7b05a9')
    stub=bytes.fromhex('3f100071550080523530951ac0035fd6')
    delta=cave-site;assert delta%4==0 and -(1<<27)<=delta<(1<<27)
    branch=struct.pack('<I',0x94000000|((delta//4)&0x3ffffff))
    out=bytearray(data);out[off+site:off+site+4]=branch;out[off+cave:off+cave+16]=stub
    for at,expected in [(0x44b9e4,'01008052'),(0xe523f4,'020f8052'),(0xe523fc,'01cd42f9'),(0x5648bc,'1f2003d5')]:
        assert out[off+at:off+at+4]==bytes.fromhex(expected)
    restored=bytearray(out);restored[off+site:off+site+4]=data[off+site:off+site+4];restored[off+cave:off+cave+16]=bytes(16)
    assert restored==data
    return bytes(out),{'site':hex(site),'branch':branch.hex(),'cave':hex(cave),'stub':stub.hex(),'invalid_tab_fallback':2}

def patch_feed(data,codec):
    original,plain=codec.unpack_feed(data);assert codec.transform(plain)==data
    out=copy.deepcopy(original);changes=[]
    renew={'unlimited_gacha_01','unlimited_gacha_02','unlimited_gacha_03','mystery_box_gacha','loot_gacha_1','loot_gacha_2','loot_gacha_3','special_gacha_02'}
    prices={p['item']:p for p in out['offline_store']['prices']}
    for cat,portals in out['game']['LiveOps']['Portals'].items():
        for p in portals:
            if p['Id'] in renew:
                assert p['Id'] in prices
                assert any(b['type']=='offline' and b['price'] for b in prices[p['Id']]['billing_methods'])
                if p['Id']=='special_gacha_02': assert len(p['FixedPoolPrices'])==len(p['RewardObject'])==10
                new='2040-12-31'
            elif p['Id']=='special_gacha_01':
                assert not p['FixedPoolPrices'];new='2019-12-31'
            else: continue
            changes.append({'category':cat,'id':p['Id'],'before':p['EndDate'],'after':new});p['EndDate']=new
    assert len(changes)==9
    restored=copy.deepcopy(out)
    for c in changes:
        matches=[p for p in restored['game']['LiveOps']['Portals'][c['category']] if p['Id']==c['id']]
        assert len(matches)==1;matches[0]['EndDate']=c['before']
    assert restored==original
    payload=json.dumps(out,separators=(',',':'),ensure_ascii=True).encode()
    encoded=struct.pack('<I',len(payload))+payload
    encoded+=hashlib.md5(encoded).hexdigest().upper().encode();encoded+=bytes((-len(encoded))%4)
    result=codec.transform(encoded);checked,_=codec.unpack_feed(result);assert checked==out
    return result,changes

def repair_textures(z):
    archives={};models={'Suit_SpiderX.bdae','Suit_Lasher.bdae'};locations={};fallback=None
    for name in z.namelist():
        if not (name.startswith(ROOT+'data_final/file') and name.endswith('.dat')):continue
        raw=z.read(name)
        try: arc=zipfile.ZipFile(io.BytesIO(raw))
        except zipfile.BadZipFile:continue
        if 'Jennix_S_low.TGA' in arc.namelist():
            assert fallback is None;fallback=read(arc,'Jennix_S_low.TGA')
        found=models.intersection(arc.namelist())
        for model in found:
            assert model not in locations;locations[model]=name
            with zipfile.ZipFile(io.BytesIO(read(arc,model))) as nested:
                b=nested.read('little_endian_not_quantized.bdae')
                assert b'Jennix_S.TGA\0' in b
        if found:archives[name]=raw
    assert set(locations)==models and fallback is not None
    assert len(fallback)==32820
    replacements={};report=[]
    for name,raw in archives.items():
        original=zipfile.ZipFile(io.BytesIO(raw));assert 'Jennix_S.TGA' not in original.namelist()
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as dest:
            for item in original.infolist():dest.writestr(copy.copy(item),read(original,item.filename))
            dest.writestr('Jennix_S.TGA',fallback,compress_type=zipfile.ZIP_DEFLATED)
        result=stream.getvalue()
        # Preserve the engine's custom first local header if present.
        if raw[:4]==b'QM\x06\x08':result=raw[:4]+result[4:]
        with zipfile.ZipFile(io.BytesIO(result)) as dest:
            assert set(dest.namelist())==set(original.namelist())|{'Jennix_S.TGA'}
            assert read(dest,'Jennix_S.TGA')==fallback
            for item in original.infolist():assert read(dest,item.filename)==read(original,item.filename)
        replacements[name]=result
        report.append({'archive':name,'alias':'Jennix_S.TGA','source':'Jennix_S_low.TGA','source_sha256':sha(fallback),'original_members_unchanged':True})
    return replacements,report

def main():
    source,output,report=map(Path,sys.argv[1:4]);assert sha(source.read_bytes())==SOURCE_SHA
    codec_path=Path(__file__).with_name('patch-portal-test2.py')
    if not codec_path.exists():codec_path=Path(__file__).with_name('patch_portal_test2.py')
    spec=importlib.util.spec_from_file_location('codec',codec_path);codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)
    with zipfile.ZipFile(source) as z:
        binary,guard=patch_binary(z.read(BINARY));feed,dates=patch_feed(z.read(FEED),codec)
        replacements,textures=repair_textures(z);replacements.update({BINARY:binary,FEED:feed})
        with zipfile.ZipFile(output,'w') as dest:
            for item in z.infolist():dest.writestr(copy.copy(item),replacements.get(item.filename,z.read(item.filename)))
        with zipfile.ZipFile(output) as dest:
            assert dest.testzip() is None and set(z.namelist())==set(dest.namelist())
            for item in z.infolist():
                if item.filename in replacements:assert dest.read(item.filename)==replacements[item.filename]
                else:assert dest.read(item.filename)==z.read(item.filename)
    assert sha(source.read_bytes())==SOURCE_SHA
    report.mkdir(parents=True,exist_ok=True)
    (report/'verification.json').write_text(json.dumps({'test':'Test5 safe fixes','input_sha256':SOURCE_SHA,'output_sha256':sha(output.read_bytes()),'binary_sha256':sha(binary),'portal_guard':guard,'portal_dates':dates,'texture_fallbacks':textures,'changed_entries':list(replacements),'fps_120_preserved':True,'tutorial_exit_patch_preserved':True,'original_members_verified':True,'zip_crc_verified':True,'save_files_modified':False,'runtime_verified':False,'limitations':['Authentic boss skins cannot be reconstructed from duplicated assets.','Unknown IronSpiderNew s.tga texture is left untouched.','2099 _099 names are texture identifiers with valid 2099 file URLs; no repair needed.','Catalogue transactions and progression require device testing.']},indent=2))
    print('Test5 static verification passed. Output SHA256:',sha(output.read_bytes()))
if __name__=='__main__':main()
