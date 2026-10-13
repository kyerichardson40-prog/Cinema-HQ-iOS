import io,json,re,struct,sys,zipfile,zlib
from pathlib import Path
source=next(Path(sys.argv[1]).glob('*.ipa'));out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
def read(arc,name):
 try:return arc.read(name)
 except zipfile.BadZipFile:
  i=arc.getinfo(name);f=arc.fp;f.seek(i.header_offset);h=f.read(30);assert h[:4] in [b'PK\x03\x04',b'QM\x06\x08'];a,b=struct.unpack_from('<HH',h,26);f.seek(a+b,1);v=f.read(i.compress_size)
  if i.compress_type==8:v=zlib.decompress(v,-15)
  else:assert i.compress_type==0
  assert zlib.crc32(v)&0xffffffff==i.CRC;return v
names=[]
with zipfile.ZipFile(source) as z:
 headers=[];outer=[]
 for n in z.namelist():
  outer.append({'name':n,'size':z.getinfo(n).file_size})
  if re.search(r'\.swf$|\.gfx$|file000001\.dat|file000001\.dat\.key|plantext',n,re.I):
   (out/Path(n).name).write_bytes(z.read(n))
  if not re.fullmatch(r'Payload/Spiderman.app/data_final/file\d+\.dat',n):continue
  raw=z.read(n);headers.append({'name':n,'size':len(raw),'first128':raw[:128].hex()})
  try:arc=zipfile.ZipFile(io.BytesIO(raw))
  except zipfile.BadZipFile:continue
  if n.endswith('file000001.dat'):(out/'swfs_members.json').write_text(json.dumps(arc.namelist()))
  for name in arc.namelist():
   if name.lower().endswith('.swf') or re.search('pause_sheet',name,re.I):
    names.append({'archive':n,'name':name,'size':arc.getinfo(name).file_size})
    if re.search(r'topbar|hud|pause|settings|options|common',name,re.I):
     target=out/Path(name).name;target.write_bytes(read(arc,name))
(out/'asset_names.json').write_text(json.dumps(names,indent=2))
(out/'outer_names.json').write_text(json.dumps(outer,indent=2))
(out/'file_headers.json').write_text(json.dumps(headers,indent=2))
print('Extracted native HUD, top bar, settings, and pause assets')
