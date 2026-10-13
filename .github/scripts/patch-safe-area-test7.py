"""Test7: load an isolated MainGLView safe-area adapter; preserve Test6 code."""
import copy,hashlib,json,struct,sys,zipfile
from pathlib import Path
SOURCE_SHA='92638beefa04de64a1a791a4acf0e4b3f6ea396c50399f2bd8882bf980f98d60'
BINARY_SHA='a9f0b33e564e3e718f7b49130ae9e630f818f2c5019198cfccce75b9f9069f10'
BINARY='Payload/Spiderman.app/Spiderman'
LIBRARY='Payload/Spiderman.app/Frameworks/SMUSafeArea.dylib'
LOAD_PATH='@loader_path/Frameworks/SMUSafeArea.dylib'
def sha(data):return hashlib.sha256(data).hexdigest()
def commands(data,off=0):
    count,sz=struct.unpack_from('<II',data,off+16);cursor=off+32;items=[]
    for _ in range(count):
        cmd,length=struct.unpack_from('<II',data,cursor);assert length>=8 and length%8==0
        items.append((cmd,cursor,length));cursor+=length
    assert cursor==off+32+sz
    return items,cursor
def main():
    source,library,output,report=map(Path,sys.argv[1:5]);assert sha(source.read_bytes())==SOURCE_SHA
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
        arms=[struct.unpack_from('>IIIII',original,8+i*20) for i in range(struct.unpack_from('>I',original,4)[0])]
        off=next(s[2] for s in arms if s[0]==0x100000c)
        items,end=commands(original,off);starts=[]
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
        with zipfile.ZipFile(output,'w') as dest:
            for item in z.infolist():dest.writestr(copy.copy(item),binary if item.filename==BINARY else z.read(item.filename))
            dest.writestr(LIBRARY,dylib,compress_type=zipfile.ZIP_DEFLATED)
        with zipfile.ZipFile(output) as dest:
            assert dest.testzip() is None and set(dest.namelist())==set(z.namelist())|{LIBRARY}
            assert dest.read(BINARY)==binary and dest.read(LIBRARY)==dylib
            for item in z.infolist():
                if item.filename!=BINARY:assert dest.read(item.filename)==z.read(item.filename)
    assert sha(source.read_bytes())==SOURCE_SHA
    report.mkdir(parents=True,exist_ok=True)
    (report/'verification.json').write_text(json.dumps({'test':'Test7 Dynamic Island safe area','input_sha256':SOURCE_SHA,'output_sha256':sha(output.read_bytes()),'binary_sha256':sha(binary),'library_sha256':sha(dylib),'load_path':LOAD_PATH,'header_only_change':True,'test6_instructions_preserved':True,'all_existing_resources_unchanged':True,'zip_crc_verified':True,'library_dependencies':deps,'library_constructor_verified':has_initializer,'initializer_format':initializer_format,'geometry_tests':'Compiled shared C geometry tests passed on macOS before iOS adapter build.','save_files_modified':False,'runtime_verified':False,'behaviour':'Only MainGLView is fitted to the window safe area. Existing framebuffer layout and view-local touch handling are retained. No fixed device dimensions are used.'},indent=2))
    print('Test7 archive verification passed:',sha(output.read_bytes()))
if __name__=='__main__':main()
