import copy,hashlib,io,json,plistlib,re,struct,sys,zipfile
from pathlib import Path
SOURCE_SHA='c194ce8b0063ebf42d0b9add720be8c7a6dc8fdeecdbae21e309d34468c57e75'
BINARY_SHA='7da6f8b352e2f2803b615e6999c846a640f8f0784cee4ac454703818431e18d2'
BINARY='Payload/Spiderman.app/Spiderman';INFO='Payload/Spiderman.app/Info.plist'
def sha(b):return hashlib.sha256(b).hexdigest()
def main():
 source,output,report=map(Path,sys.argv[1:4]);report.mkdir(parents=True,exist_ok=True)
 assert sha(source.read_bytes())==SOURCE_SHA
 with zipfile.ZipFile(source) as z:
  original=z.read(BINARY);assert sha(original)==BINARY_SHA;patched=bytearray(original)
  slices=[struct.unpack_from('>IIIII',original,8+i*20) for i in range(struct.unpack_from('>I',original,4)[0])]
  arm=next(s for s in slices if s[0]==0x100000c);offset=arm[2]
  changes=[(0xe523f4,'626a68f8','020f8052','Request 120 frames per second'),(0xe523fc,'01c942f9','01cd42f9','Use setPreferredFramesPerSecond: selector')]
  for site,before,after,label in changes:
   assert original[offset+site:offset+site+4]==bytes.fromhex(before),(hex(site),'unexpected opcode')
   patched[offset+site:offset+site+4]=bytes.fromhex(after)
  assert patched[offset+0x5648bc:offset+0x5648c0]==bytes.fromhex('1f2003d5')
  info=plistlib.loads(z.read(INFO));newinfo=dict(info);newinfo['CADisableMinimumFrameDurationOnPhone']=True
  info_bytes=plistlib.dumps(newinfo,fmt=plistlib.FMT_BINARY,sort_keys=False)
  with zipfile.ZipFile(output,'w') as out:
   for item in z.infolist():out.writestr(copy.copy(item),patched if item.filename==BINARY else info_bytes if item.filename==INFO else z.read(item.filename))
  with zipfile.ZipFile(output) as out:
   assert out.testzip() is None
   assert out.read(BINARY)==patched
   assert plistlib.loads(out.read(INFO))==newinfo
   for item in z.infolist():
    if item.filename not in [BINARY,INFO]:
     other=out.getinfo(item.filename);assert (item.file_size,item.CRC)==(other.file_size,other.CRC)
  assets=[]
  for leaf in ['file000002.dat','file000010.dat']:
   data=z.read('Payload/Spiderman.app/data_final/'+leaf)
   rec={'archive':leaf,'tail128':data[-128:].hex(),'boss_entries':[]}
   try:
    try:archive=zipfile.ZipFile(io.BytesIO(data));rec['format']='ZIP'
    except zipfile.BadZipFile:
     fixed=data
     for a,b in [(b'QM\x06\x08',b'PK\x03\x04'),(b'QM\x04\x06',b'PK\x01\x02'),(b'QM\x08\x0a',b'PK\x05\x06')]:fixed=fixed.replace(a,b)
     archive=zipfile.ZipFile(io.BytesIO(fixed));rec['format']='ZIP with translated signatures'
    rec['entry_count']=len(archive.namelist())
    for n in archive.namelist():
     if re.search('goblin',n,re.I):
      content=archive.read(n);entry={'name':n,'size':len(content),'sha256':sha(content)}
      rec['boss_entries'].append(entry)
      if len(content)<4000000:
       safe=re.sub('[^a-zA-Z0-9_.-]','_',n);(report/('asset_'+safe)).write_bytes(content)
   except Exception as e:rec['inspection_error']=str(e)
   assets.append(rec)
  (report/'boss_assets.json').write_text(json.dumps(assets,indent=2))
 assert sha(source.read_bytes())==SOURCE_SHA
 (report/'verification.json').write_text(json.dumps({'test':'Test3 120 FPS request','input_sha256':SOURCE_SHA,'output_sha256':sha(output.read_bytes()),'binary_patches':[{'offset':hex(p[0]),'before':p[1],'after':p[2],'purpose':p[3]} for p in changes],'promotion_opt_in':True,'portal_feed_unchanged':True,'all_other_assets_unchanged':True,'save_files_modified':False,'runtime_verified':False},indent=2))
 print('Test3 packaged and verified; boss assets inspected')
if __name__=='__main__':main()
