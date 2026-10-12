"""Test6: stop forced tutorial revives through the native no-revive result."""
import copy,hashlib,json,struct,sys,zipfile
from pathlib import Path

SOURCE_SHA='b1f35ea79e08ab6b6ec977e472311fbf75bddfdaeb0333d7e35a77f4e1cc45e3'
BINARY_SHA='abb50a357547be6e48f9774278adf262cd29232cd8fec590e2b43ef1313b3e43'
BINARY='Payload/Spiderman.app/Spiderman'
SITE=0x44b90c;CAVE=0x2010;NO_REVIVE=0x44ba20;NORMAL_CAP=0x44ba08
def sha(data):return hashlib.sha256(data).hexdigest()
def branch(pc,target,condition=None):
    delta=target-pc;assert delta%4==0
    if condition is None:
        assert -(1<<27)<=delta<(1<<27)
        word=0x14000000|((delta//4)&0x3ffffff)
    else:
        assert -(1<<20)<=delta<(1<<20)
        word=0x54000000|(((delta//4)&0x7ffff)<<5)|condition
    return struct.pack('<I',word)

def make_patch(data):
    assert sha(data)==BINARY_SHA
    slices=[struct.unpack_from('>IIIII',data,8+i*20) for i in range(struct.unpack_from('>I',data,4)[0])]
    arm=next(s for s in slices if s[0]==0x100000c);offset=arm[2]
    assert data[offset+SITE:offset+SITE+4]==bytes.fromhex('1f010071')
    assert data[offset+SITE-4:offset+SITE]==bytes.fromhex('685a41b9')
    assert data[offset+SITE+4:offset+SITE+8]==bytes.fromhex('cd070054')
    assert data[offset+NO_REVIVE:offset+NO_REVIVE+8]==bytes.fromhex('00008052f4ffff17')
    assert data[offset+CAVE:offset+CAVE+24]==bytes(24)
    assert data[offset+0x2000:offset+0x2010]==bytes.fromhex('3f100071550080523530951ac0035fd6')
    ncmds,sizeofcmds=struct.unpack_from('<II',data,offset+16)
    assert 32+sizeofcmds<=CAVE
    cursor=offset+32;starts=[]
    for _ in range(ncmds):
        cmd,length=struct.unpack_from('<II',data,cursor)
        if cmd==0x19:
            count=struct.unpack_from('<I',data,cursor+64)[0]
            for j in range(count):
                sec=cursor+72+80*j
                sectionoff=struct.unpack_from('<I',data,sec+48)[0]
                if sectionoff:starts.append(sectionoff)
        cursor+=length
    assert starts and min(starts)>=CAVE+24
    # A conditional branch reaches only +/-1 MiB; use a nearby split plus two
    # full-range branches to the existing native paths (roughly 4.5 MiB away).
    stub=bytes.fromhex('1f010071')+branch(CAVE+4,CAVE+12,12)+branch(CAVE+8,NORMAL_CAP)+branch(CAVE+12,NO_REVIVE)
    out=bytearray(data);out[offset+SITE:offset+SITE+4]=branch(SITE,CAVE);out[offset+CAVE:offset+CAVE+len(stub)]=stub
    restored=bytearray(out);restored[offset+SITE:offset+SITE+4]=data[offset+SITE:offset+SITE+4];restored[offset+CAVE:offset+CAVE+len(stub)]=bytes(len(stub))
    assert restored==data
    for at,expected in [(0x44b9e4,'01008052'),(0xe523f4,'020f8052'),(0xe523fc,'01cd42f9'),(0x5648bc,'1f2003d5'),(0x56467c,'6176ea97')]:
        assert out[offset+at:offset+at+4]==bytes.fromhex(expected)
    return bytes(out),{'site':hex(SITE),'before':'1f010071','after':branch(SITE,CAVE).hex(),'cave':hex(CAVE),'stub':stub.hex(),'tutorial_positive_destination':hex(NO_REVIVE),'ordinary_destination':hex(NORMAL_CAP),'normal_revive_cap_unchanged':True}

def verify_execution(binary,offset):
    from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE
    from unicorn.arm64_const import UC_ARM64_REG_X8,UC_ARM64_REG_X19,UC_ARM64_REG_X0,UC_ARM64_REG_SP,UC_ARM64_REG_X30
    base=0x100000000;tested=[]
    for tutorial in [0,1,2,100,0x7fffffff,0xffffffff,0x80000000]:
        emu=Uc(UC_ARCH_ARM64,UC_MODE_ARM);emu.mem_map(base,0x500000)
        emu.mem_write(base+0x2000,binary[offset+0x2000:offset+0x2028])
        emu.mem_write(base+0x44b900,binary[offset+0x44b900:offset+0x44ba28])
        state=0x200000000;emu.mem_map(state,0x1000);emu.mem_write(state+0x158,struct.pack('<I',tutorial))
        emu.reg_write(UC_ARM64_REG_X19,state);emu.reg_write(UC_ARM64_REG_X0,0xabcdef);emu.reg_write(UC_ARM64_REG_SP,state+0x800);emu.reg_write(UC_ARM64_REG_X30,0x12345678)
        reached=[]
        def hook(uc,address,size,user):
            if address in (base+NORMAL_CAP,base+NO_REVIVE):reached.append(address-base);uc.emu_stop()
        hook_id=emu.hook_add(UC_HOOK_CODE,hook);emu.emu_start(base+SITE-4,base+0x500000,count=20)
        positive=0<tutorial<0x80000000
        assert reached==[NO_REVIVE if positive else NORMAL_CAP],(tutorial,reached)
        assert emu.reg_read(UC_ARM64_REG_X19)==state and emu.reg_read(UC_ARM64_REG_SP)==state+0x800 and emu.reg_read(UC_ARM64_REG_X30)==0x12345678
        if positive:
            # Execute the existing return-zero instruction and branch to the
            # existing stack restoration, without substituting a new epilogue.
            emu.hook_del(hook_id);emu.emu_start(base+NO_REVIVE,base+0x44b9f4,count=2)
            assert emu.reg_read(UC_ARM64_REG_X0)==0
        tested.append({'tutorial_state':tutorial,'destination':hex(reached[0]),'native_return_zero':positive})
    return tested

def main():
    source,output,report=map(Path,sys.argv[1:4]);assert sha(source.read_bytes())==SOURCE_SHA
    with zipfile.ZipFile(source) as z:
        original=z.read(BINARY);binary,patch=make_patch(original)
        offset=next(struct.unpack_from('>IIIII',original,8+i*20)[2] for i in range(struct.unpack_from('>I',original,4)[0]) if struct.unpack_from('>I',original,8+i*20)[0]==0x100000c)
        executed=verify_execution(binary,offset)
        with zipfile.ZipFile(output,'w') as dest:
            for item in z.infolist():dest.writestr(copy.copy(item),binary if item.filename==BINARY else z.read(item.filename))
        with zipfile.ZipFile(output) as dest:
            assert dest.testzip() is None and set(z.namelist())==set(dest.namelist())
            assert dest.read(BINARY)==binary
            for item in z.infolist():
                if item.filename!=BINARY:assert dest.read(item.filename)==z.read(item.filename)
    assert sha(source.read_bytes())==SOURCE_SHA
    report.mkdir(parents=True,exist_ok=True)
    (report/'verification.json').write_text(json.dumps({'test':'Test6 tutorial death exit','input_sha256':SOURCE_SHA,'output_sha256':sha(output.read_bytes()),'binary_sha256':sha(binary),'patch':patch,'arm64_execution_tests':executed,'all_other_archive_entries_unchanged':True,'fps_120_preserved':True,'test5_portal_and_texture_fixes_preserved':True,'save_files_modified':False,'runtime_verified':False,'behaviour':'Tutorial deaths return no-revive through the existing native mission-end flow. Ordinary mission revival and caps are unchanged. Tutorial progress is not marked complete.'},indent=2))
    print('Test6 verified:',sha(output.read_bytes()))
if __name__=='__main__':main()
