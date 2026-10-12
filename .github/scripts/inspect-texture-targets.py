import io,json,re,struct,sys,zipfile,zlib
from pathlib import Path
source=next(Path(sys.argv[1]).glob('*.ipa'));out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
selected={'Suit_2099_New.bdae','Suit_SpiderX.bdae','Suit_Lasher.bdae','Suit_IronSpiderNew.bdae'}
def read(arc,n):
 try:return arc.read(n)
 except zipfile.BadZipFile:
  i=arc.getinfo(n);f=arc.fp;f.seek(i.header_offset);h=f.read(30);assert h[:4] in [b'PK\x03\x04',b'QM\x06\x08'];a,b=struct.unpack_from('<HH',h,26);f.seek(a+b,1);v=f.read(i.compress_size)
  if i.compress_type==8:v=zlib.decompress(v,-15)
  else:assert i.compress_type==0
  assert zlib.crc32(v)&0xffffffff==i.CRC;return v
candidates=[]
with zipfile.ZipFile(source) as z:
 for n in z.namelist():
  if not re.fullmatch(r'Payload/Spiderman.app/data_final/file\d+\.dat',n):continue
  b=z.read(n)
  try:arc=zipfile.ZipFile(io.BytesIO(b))
  except zipfile.BadZipFile:continue
  for name in arc.namelist():
   if name in selected:(out/name).write_bytes(read(arc,name))
   if re.search(r'2099.*new|new.*2099|jennix|iron.*spider.*new|white\.tga|black\.tga',name,re.I):candidates.append({'archive':n.rsplit('/',1)[-1],'name':name,'size':arc.getinfo(name).file_size})
(out/'candidates.json').write_text(json.dumps(candidates,indent=2))
print('Extracted texture reference models and candidate names')
