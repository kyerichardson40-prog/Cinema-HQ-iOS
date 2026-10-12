"""Test4: allow declining revives during tutorials; preserve Test3 FPS and portals."""
import copy,hashlib,json,struct,sys,zipfile
from pathlib import Path
SOURCE_SHA='44c4d01447851a00c58d82e21c01aae729e1c267e31bd9193b4e6154734982dc'
BINARY='Payload/Spiderman.app/Spiderman'
def sha(b):return hashlib.sha256(b).hexdigest()
def main():
 source,output,report=map(Path,sys.argv[1:4]);assert sha(source.read_bytes())==SOURCE_SHA
 with zipfile.ZipFile(source) as z:
  original=z.read(BINARY);patched=bytearray(original)
  slices=[struct.unpack_from('>IIIII',original,8+i*20) for i in range(struct.unpack_from('>I',original,4)[0])]
  arm=next(s for s in slices if s[0]==0x100000c);offset=arm[2];site=0x44b9e4
  assert original[offset+site:offset+site+4]==bytes.fromhex('e1d79f1a')
  assert original[offset+0xe523f4:offset+0xe523f8]==bytes.fromhex('020f8052')
  assert original[offset+0xe523fc:offset+0xe52400]==bytes.fromhex('01cd42f9')
  assert original[offset+0x5648bc:offset+0x5648c0]==bytes.fromhex('1f2003d5')
  # Pass false to isTutorialContinues in the revive prompt only.
  patched[offset+site:offset+site+4]=bytes.fromhex('01008052')
  with zipfile.ZipFile(output,'w') as dest:
   for item in z.infolist():dest.writestr(copy.copy(item),patched if item.filename==BINARY else z.read(item.filename))
  with zipfile.ZipFile(output) as dest:
   assert dest.testzip() is None
   assert dest.read(BINARY)==patched
   assert set(z.namelist())==set(dest.namelist())
   for item in z.infolist():
    if item.filename!=BINARY:
     other=dest.getinfo(item.filename);assert (item.CRC,item.file_size)==(other.CRC,other.file_size)
 assert sha(source.read_bytes())==SOURCE_SHA
 report.mkdir(parents=True,exist_ok=True)
 (report/'verification.json').write_text(json.dumps({'test':'Test4 tutorial revive exit','input_sha256':SOURCE_SHA,'output_sha256':sha(output.read_bytes()),'binary_sha256':sha(patched),'patch':{'offset':hex(site),'before':'e1d79f1a','after':'01008052','purpose':'Set isTutorialContinues to false for the revive prompt, permitting decline/quit'},'fps_patch_preserved':True,'portal_feed_unchanged':True,'all_other_archive_entries_unchanged':True,'save_files_modified':False,'runtime_verified':False},indent=2))
 print('Test4 verified: one ARM64 instruction changed; all prior fixes retained')
if __name__=='__main__':main()
