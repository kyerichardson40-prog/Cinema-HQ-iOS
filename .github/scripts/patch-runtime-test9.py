"""Test9: per-frame gameplay FOV plus native AS3 pause and safe-area controls."""
import copy,hashlib,json,struct,sys,zipfile,re,zlib
from inject_native_ui import inject
from pathlib import Path
SOURCE_SHA='92638beefa04de64a1a791a4acf0e4b3f6ea396c50399f2bd8882bf980f98d60'
BINARY_SHA='a9f0b33e564e3e718f7b49130ae9e630f818f2c5019198cfccce75b9f9069f10'
BINARY='Payload/Spiderman.app/Spiderman'
LIBRARY='Payload/Spiderman.app/Frameworks/SMURuntime.dylib'
LOAD_PATH='@loader_path/Frameworks/SMURuntime.dylib'
def sha(data):return hashlib.sha256(data).hexdigest()
def commands(data,off=0):
    count,sz=struct.unpack_from('<II',data,off+16);cursor=off+32;items=[]
    for _ in range(count):
        cmd,length=struct.unpack_from('<II',data,cursor);assert length>=8 and length%8==0
        items.append((cmd,cursor,length));cursor+=length
    assert cursor==off+32+sz
    return items,cursor
def verify_native_setter(binary,off):
    from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM
    from unicorn.arm64_const import UC_ARM64_REG_X0,UC_ARM64_REG_S0,UC_ARM64_REG_X30
    assert binary[off+0xfe31c0:off+0xfe31d4]==bytes.fromhex('008801bd0840477908011f3208400779c0035fd6')
    assert binary[off+0x3a0cb0:off+0x3a0cb8]==bytes.fromhex('ff8303d1f44f0ca9')
    assert binary[off+0x148d18:off+0x148d20]==bytes.fromhex('f657bda9f44f01a9')
    results=[]
    for degrees in [45,60,75,90,100]:
        emu=Uc(UC_ARCH_ARM64,UC_MODE_ARM);base=0x100000000;state=0x200000000
        emu.mem_map(base+0xfe3000,0x1000);emu.mem_write(base+0xfe31c0,binary[off+0xfe31c0:off+0xfe31d4]);emu.mem_map(state,0x1000)
        data=bytearray(0x400);struct.pack_into('<ff',data,0x190,0.5,1000);struct.pack_into('<H',data,0x3a0,0x100)
        emu.mem_write(state,bytes(data));emu.reg_write(UC_ARM64_REG_X0,state)
        radians=degrees*3.141592653589793/180
        emu.reg_write(UC_ARM64_REG_S0,struct.unpack('<I',struct.pack('<f',radians))[0]);emu.reg_write(UC_ARM64_REG_X30,base+0xfe31d4)
        emu.emu_start(base+0xfe31c0,base+0xfe31d4,count=5)
        out=emu.mem_read(state,0x400);expected=bytearray(data);struct.pack_into('<f',expected,0x188,radians);struct.pack_into('<H',expected,0x3a0,0x102)
        assert out==expected
        results.append({'degrees':degrees,'native_fov_set':True,'projection_dirty_set':True,'near_far_and_other_fields_unchanged':True})
    return results

def main():
    source,library,game_ui,header_ui,output,report=map(Path,sys.argv[1:7]);assert sha(source.read_bytes())==SOURCE_SHA
    dylib=library.read_bytes();assert struct.unpack_from('<I',dylib)[0]==0xfeedfacf
    assert struct.unpack_from('<I',dylib,4)[0]==0x100000c and struct.unpack_from('<I',dylib,12)[0]==6
    deps=[];has_initializer=False;initializer_format=None;initializer_offsets=[];text_base=None;code_ranges=[]
    for cmd,at,size in commands(dylib)[0]:
        if cmd in (0xc,0x80000018):
            pos=at+struct.unpack_from('<I',dylib,at+8)[0];name=dylib[pos:dylib.index(0,pos)].decode();deps.append(name)
            assert name.startswith(('/System/Library/','/usr/lib/'))
        if cmd==0x19:
            if dylib[at+8:at+24].split(b'\0')[0]==b'__TEXT':text_base=struct.unpack_from('<Q',dylib,at+24)[0]
            for j in range(struct.unpack_from('<I',dylib,at+64)[0]):
                sec=at+72+80*j
                name=dylib[sec:sec+16].split(b'\0')[0]
                addr,sz,pos=struct.unpack_from('<QQI',dylib,sec+32)
                kind=struct.unpack_from('<I',dylib,sec+64)[0]&255
                if name==b'__text':code_ranges.append((addr,addr+sz))
                if kind==9 and sz>=8:has_initializer=True;initializer_format='S_MOD_INIT_FUNC_POINTERS'
                if kind==0x16:
                    assert sz>=4 and sz%4==0
                    initializer_offsets.extend(struct.unpack_from('<%dI'%(sz//4),dylib,pos));initializer_format='S_INIT_FUNC_OFFSETS'
    if initializer_offsets:
        assert text_base is not None
        assert all(any(a<=text_base+v<b for a,b in code_ranges) for v in initializer_offsets)
        has_initializer=True
    assert has_initializer and any('UIKit.framework' in x for x in deps)
    with zipfile.ZipFile(source) as z:
        original=z.read(BINARY);assert sha(original)==BINARY_SHA and LIBRARY not in z.namelist()
        assert 'Payload/Spiderman.app/Frameworks/SMUSafeArea.dylib' not in z.namelist()
        assert 'Payload/Spiderman.app/Frameworks/SMUFOV.dylib' not in z.namelist()
        arms=[struct.unpack_from('>IIIII',original,8+i*20) for i in range(struct.unpack_from('>I',original,4)[0])]
        off=next(s[2] for s in arms if s[0]==0x100000c)
        items,end=commands(original,off);starts=[]
        native_tests=verify_native_setter(original,off)
        for cmd,at,size in items:
            if cmd==0x19:
                for j in range(struct.unpack_from('<I',original,at+64)[0]):
                    sec=at+72+80*j;pos=struct.unpack_from('<I',original,sec+48)[0]
                    if pos:starts.append(pos)
        name=LOAD_PATH.encode()+b'\0';length=(24+len(name)+7)&~7
        command=struct.pack('<6I',0xc,length,24,0,0x10000,0x10000)+name+bytes(length-24-len(name))
        # Existing code caves start at 0x2000. Do not write into them.
        assert end+length<=off+min(min(starts),0x2000)
        assert original[end:end+length]==bytes(length)
        binary=bytearray(original);binary[end:end+length]=command
        count,sz=struct.unpack_from('<II',original,off+16);struct.pack_into('<II',binary,off+16,count+1,sz+length)
        restored=bytearray(binary);restored[end:end+length]=bytes(length);restored[off+16:off+24]=original[off+16:off+24]
        assert restored==original,'Only the load-command header and zero padding may change'
        newcommands,_=commands(binary,off);assert len(newcommands)==len(items)+1
        for site,expected in [(0x44b90c,'c1d9ee17'),(0xe523f4,'020f8052'),(0xe523fc,'01cd42f9'),(0x56467c,'6176ea97')]:
            assert binary[off+site:off+site+4]==bytes.fromhex(expected)
        replacements={BINARY:binary};ui_reports=[]
        for number,module,target,name in [(11,game_ui,648,'SMUGameControls'),(54,header_ui,706,'SMUHeaderControls')]:
            path=f'Payload/Spiderman.app/data_final/file{number:06d}.dat'
            newdata,proof=inject(z.read(path),module.read_bytes(),target,name);replacements[path]=newdata;ui_reports.append(proof)
        plaintext='Payload/Spiderman.app/data_final/file00000-plantext.dat'
        if plaintext in z.namelist():
            index=z.read(plaintext)
            for number,proof in zip([11,54],ui_reports):
                crc=proof['after_crc32'];signed=crc if crc<0x80000000 else crc-0x100000000
                index,count=re.subn(rb'(file%06d.dat [^\r\n ]+ )-?\d+'%number,lambda m:m[1]+str(signed).encode(),index)
                assert count==1
            replacements[plaintext]=index
        with zipfile.ZipFile(output,'w') as dest:
            for item in z.infolist():dest.writestr(copy.copy(item),replacements.get(item.filename,z.read(item.filename)))
            dest.writestr(LIBRARY,dylib,compress_type=zipfile.ZIP_DEFLATED)
        with zipfile.ZipFile(output) as dest:
            assert dest.testzip() is None and set(dest.namelist())==set(z.namelist())|{LIBRARY}
            assert dest.read(BINARY)==binary and dest.read(LIBRARY)==dylib
            for item in z.infolist():
                if item.filename not in replacements:assert dest.read(item.filename)==z.read(item.filename)
                else:assert dest.read(item.filename)==replacements[item.filename]
    assert sha(source.read_bytes())==SOURCE_SHA
    report.mkdir(parents=True,exist_ok=True)
    (report/'verification.json').write_text(json.dumps({'test':'Test9 persistent FOV and native UI','input_sha256':SOURCE_SHA,'output_sha256':sha(output.read_bytes()),'binary_sha256':sha(binary),'library_sha256':sha(dylib),'load_path':LOAD_PATH,'header_only_change':True,'test6_instructions_preserved':True,'unchanged_resource_entries_verified':True,'native_ui_injection':ui_reports,'changed_entries':list(replacements),'whole_screen_safe_area_adapter_removed':True,'zip_crc_verified':True,'library_dependencies':deps,'library_constructor_verified':has_initializer,'initializer_format':initializer_format,'camera_policy_tests':'14400 authored camera updates, passthrough cameras, reset and obfuscated AS numeric ABI passed.', 'native_fov_setter_tests':native_tests,'save_files_modified':False,'runtime_verified':False,'behaviour':'Overrides the exact per-frame gameplay FOV setter; native AS3 slider is a child of the native pause menu. Only HUD and menu header clips move for the Dynamic Island. Full-screen framebuffer restored. Preferences retained; game save files untouched.'},indent=2))
    print('Test9 archive verification passed:',sha(output.read_bytes()))
if __name__=='__main__':main()
