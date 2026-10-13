"""Emulate the compiled dylib FOV hook and the actual native setter, not a mock."""
import json,math,struct,sys,zipfile
from pathlib import Path
from unicorn import Uc,UC_ARCH_ARM64,UC_MODE_ARM,UC_HOOK_CODE
from unicorn.arm64_const import *

def main():
 ipa,library,report=map(Path,sys.argv[1:4]);d=library.read_bytes();segments=[];sections=[];p=32;symtab=None;indirect=None
 for _ in range(struct.unpack_from('<I',d,16)[0]):
  c,n=struct.unpack_from('<II',d,p)
  if c==0x19:
   vm,vs,fo,fs=struct.unpack_from('<QQQQ',d,p+24);segments.append((vm,vs,fo,fs))
   for j in range(struct.unpack_from('<I',d,p+64)[0]):
    q=p+72+80*j;sections.append((d[q:q+16].split(b'\0')[0],)+struct.unpack_from('<QQI',d,q+32)+(struct.unpack_from('<I',d,q+68)[0],struct.unpack_from('<I',d,q+72)[0]))
  if c==2:symtab=struct.unpack_from('<4I',d,p+8)
  if c==0xb:indirect=struct.unpack_from('<II',d,p+56)
  p+=n
 syms=[];names={};so,num,strings,ss=symtab
 for i in range(num):
  string,t,sect,desc,value=struct.unpack_from('<IBBHQ',d,so+i*16);name=d[strings+string:d.index(0,strings+string)].decode();syms.append(name)
  if value:names[name]=value
 def symbol(suffix):
  matches=[v for n,v in names.items() if suffix in n];assert len(matches)==1,(suffix,[(n,v) for n,v in names.items() if suffix in n]);return matches[0]
 hook=symbol('GameplayFOVSetter');globalbase=symbol('GameBase');selected=symbol('SelectedDegrees');original=symbol('OriginalSetFOV');last=symbol('LastAuthoredRadians')
 external={}
 for name,addr,size,offset,first,stride in sections:
  if name==b'__stubs':
   assert indirect and stride
   for i in range(size//stride):idx=struct.unpack_from('<I',d,indirect[0]+(first+i)*4)[0];external[addr+i*stride]=syms[idx]
 with zipfile.ZipFile(ipa) as z:binary=z.read('Payload/Spiderman.app/Spiderman')
 arms=[struct.unpack_from('>IIIII',binary,8+i*20) for i in range(struct.unpack_from('>I',binary,4)[0])];off=next(x[2] for x in arms if x[0]==0x100000c);arm=binary[off:]
 game=0x100000000;lib=0x300000000;camera=0x200000000;stack=0x400000000
 emu=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
 for vm,vs,fo,fs in segments:
  if not vs:continue
  emu.mem_map(lib+vm,(vs+4095)&~4095);emu.mem_write(lib+vm,d[fo:fo+fs])
 emu.mem_map(game+0xfe3000,4096);emu.mem_write(game+0xfe31c0,arm[0xfe31c0:0xfe31d4]);emu.mem_map(camera,4096);emu.mem_map(stack,65536)
 def putq(at,value):emu.mem_write(at,struct.pack('<Q',value))
 def putf(at,value):emu.mem_write(at,struct.pack('<f',value))
 def getf(at):return struct.unpack('<f',emu.mem_read(at,4))[0]
 def sf(reg):return struct.unpack('<f',struct.pack('<I',emu.reg_read(reg)))[0]
 calls=[]
 def external_hook(uc,address,size,_):
  name=external.get(address-lib)
  if not name:return
  calls.append(name)
  if name=='_memcmp':
   a=uc.reg_read(UC_ARM64_REG_X0);b=uc.reg_read(UC_ARM64_REG_X1);n=uc.reg_read(UC_ARM64_REG_X2)
   left=uc.mem_read(a,n);right=uc.mem_read(b,n);uc.reg_write(UC_ARM64_REG_X0,0 if left==right else 1)
  elif name in ['_roundf','_fminf','_fmaxf']:
   a=sf(UC_ARM64_REG_S0);b=sf(UC_ARM64_REG_S1)
   result=math.floor(a+0.5) if name=='_roundf' else min(a,b) if name=='_fminf' else max(a,b)
   uc.reg_write(UC_ARM64_REG_S0,struct.unpack('<I',struct.pack('<f',result))[0])
  else:raise AssertionError(('unexpected import in camera hook',name))
  uc.reg_write(UC_ARM64_REG_PC,uc.reg_read(UC_ARM64_REG_X30))
 emu.hook_add(UC_HOOK_CODE,external_hook)
 putq(lib+globalbase,game);putq(lib+original,game+0xfe31c0)
 emu.mem_write(camera,bytes(0x400));putq(camera,game+0x18d6ce0);emu.mem_write(camera+0x20,b'camera-object\0');emu.mem_write(camera+0x37,b'\x0d');putf(camera+0x18c,0.4615);putf(camera+0x190,0.5);putf(camera+0x194,1000)
 checks=[]
 def run(native,degrees,caller,eligible=True):
  putf(lib+selected,degrees);putq(camera,game+0x18d6ce0 if eligible else game+0x18d6d00)
  before=emu.mem_read(camera,0x400);emu.reg_write(UC_ARM64_REG_X0,camera);emu.reg_write(UC_ARM64_REG_S0,struct.unpack('<I',struct.pack('<f',native))[0]);emu.reg_write(UC_ARM64_REG_X30,game+caller);emu.reg_write(UC_ARM64_REG_SP,stack+0xff00)
  emu.emu_start(lib+hook,game+caller,count=300)
  after=emu.mem_read(camera,0x400);expected=bytearray(before);value=(degrees*math.pi/180) if caller==0x22d464 and eligible and degrees!=60 else native;struct.pack_into('<f',expected,0x188,value);flags=struct.unpack_from('<H',before,0x3a0)[0]|2;struct.pack_into('<H',expected,0x3a0,flags)
  assert after==expected,(native,degrees,hex(caller),getf(camera+0x188),value)
  return getf(camera+0x188)
 for degrees in [45,60,75,90,100]:
  for frame in range(240):run(0.85+(frame%50)*0.008,degrees,0x22d464)
  checks.append({'degrees':degrees,'240_consecutive_gameplay_updates_passed':True})
 authored=0.932;run(authored,90,0x22d464);assert abs(getf(lib+last)-authored)<0.00001
 run(authored,60,0x22d464);run(0.8,90,0x22cd2c);run(0.9,90,0x22d464,False)
 report.mkdir(parents=True,exist_ok=True);(report/'compiled-camera-hook-tests.json').write_text(json.dumps({'compiled_arm64_hook_verified':True,'native_setter_executed':True,'tests':checks,'reset_uses_latest_authored_fov':True,'constructor_and_other_camera_passthrough':True,'aspect_near_far_other_fields_unchanged':True,'imports_exercised':sorted(set(calls))},indent=2));print('Compiled ARM64 per-frame camera hook passed 1203 cases')
if __name__=='__main__':main()
