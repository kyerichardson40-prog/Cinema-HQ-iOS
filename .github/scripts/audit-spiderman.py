"""Read-only audit of Test4 assets and offline configuration."""
import collections,datetime,hashlib,importlib.util,io,json,re,struct,sys,zipfile,zlib
from pathlib import Path
source=next(Path(sys.argv[1]).glob('*.ipa'));out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('feed_codec',str(Path(__file__).with_name('patch-portal-test2.py')));codec=importlib.util.module_from_spec(spec);spec.loader.exec_module(codec)
def sha(b):return hashlib.sha256(b).hexdigest()
def write(name,data): (out/name).write_text(json.dumps(data,indent=2))
def read_member(archive,member):
 try:return archive.read(member)
 except zipfile.BadZipFile:
  info=archive.getinfo(member);fp=archive.fp;fp.seek(info.header_offset);head=fp.read(30)
  assert head[:4] in [b'QM\x06\x08',b'PK\x03\x04']
  name,extra=struct.unpack_from('<HH',head,26);fp.seek(name+extra,1);data=fp.read(info.compress_size)
  if info.compress_type==8:data=zlib.decompress(data,-15)
  else:assert info.compress_type==0
  assert len(data)==info.file_size and zlib.crc32(data)&0xffffffff==info.CRC
  return data
before=sha(source.read_bytes());assets={};groups=collections.defaultdict(list);refs=[];errors=[];archive_count=0
with zipfile.ZipFile(source) as z:
 static=json.loads(z.read('Payload/Spiderman.app/data_final/StaticData.json'))
 feed,_=codec.unpack_feed(z.read('Payload/Spiderman.app/data_final/InitialCRMFeed.dat'))
 today=datetime.date(2026,10,12);expired=[];active=[];future=[];invalid=[]
 for category,portals in feed['game']['LiveOps']['Portals'].items():
  for p in portals:
   rec={'category':category,'id':p['Id'],'end':p['EndDate'],'tab':p.get('Tab')}
   try:
    start=datetime.date.fromisoformat(p['StartDate']);end=datetime.date.fromisoformat(p['EndDate'])
    if end<today:expired.append(rec)
    elif start>today:future.append(rec)
    else:active.append(rec)
    if start>end:invalid.append(rec)
   except ValueError:invalid.append(rec)
 prices=feed['offline_store']['prices'];price_ids={p['item'] for p in prices};missing_prices=[p for p in active if p['id'] not in price_ids]
 write('offline_catalogue.json',{'active_portals':active,'expired_portal_count':len(expired),'expired_categories':dict(collections.Counter(p['category'] for p in expired)),'future_count':len(future),'invalid_dates':invalid,'active_without_direct_price':missing_prices,'price_item_duplicates':[k for k,v in collections.Counter(p['item'] for p in prices).items() if v>1],'note':'No direct price may be intentional for fixed-pool/VIP mechanics. Runtime testing is required.'})
 mission_results=[]
 for group in ['SocialMap','Event']:
  for kind in ['Story','Special']:
   missions=static['Missions'][group][kind];ids=[m['MissionID'] for m in missions];bad=[]
   for m in missions:
    for key,v in m.items():
     if key.startswith('Obj_') and isinstance(v,dict) and v.get('Goal',0)<=0:bad.append({'id':m['MissionID'],'objective':key,'goal':v.get('Goal')})
   mission_results.append({'group':group,'kind':kind,'count':len(missions),'duplicate_ids':[i for i,n in collections.Counter(ids).items() if n>1],'nonpositive_goals':bad})
 write('progression_and_revives.json',{'missions':mission_results,'revival_prices':static['Revival'],'gameplay':{k:v for k,v in static['Gameplay'].items() if re.search('Revive|TimeOut|Timeout|EnergyCap|DailyCashCap|InfiniteMaxBossDefeat',k)},'inventory_slots':static['InventorySlot'],'note':'These values include deliberate changes from the original mod. They are not all bugs.'})
 for n in z.namelist():
  if not re.fullmatch(r'Payload/Spiderman.app/data_final/file\d+\.dat',n):continue
  data=z.read(n)
  try:arc=zipfile.ZipFile(io.BytesIO(data))
  except zipfile.BadZipFile:continue
  archive_count+=1
  for name in arc.namelist():
   norm=name.lower().split('/')[-1];assets.setdefault(norm,[]).append(n)
   if not name.lower().endswith('.bdae') or not name.split('/')[-1].startswith('Suit_'):continue
   try:
    body=read_member(arc,name);groups[sha(body)].append(name)
    try:
     nested=zipfile.ZipFile(io.BytesIO(body));raw=read_member(nested,'little_endian_not_quantized.bdae')
    except (zipfile.BadZipFile,KeyError):raw=body
    targets={m.group().decode('ascii').replace('\\','/').split('/')[-1].lower() for m in re.finditer(rb'[A-Za-z0-9_./-]{2,120}\.tga',raw,re.I)}
    refs.extend({'suit':name,'texture':t} for t in targets)
   except Exception as e:errors.append({'archive':n,'name':name,'error':str(e)})
  arc.close()
 duplicates=[{'sha256':h,'names':names} for h,names in groups.items() if len(set(names))>1]
 missing=[r for r in refs if r['texture'] not in assets]
 write('asset_integrity.json',{'archive_count':archive_count,'indexed_asset_names':len(assets),'suit_count':sum(len(v) for v in groups.values()),'duplicate_suit_groups':duplicates,'missing_texture_references':missing,'read_errors':errors,'note':'Some duplicates are intentional aliases. Missing references may be supplied externally; neither proves an on-device fault alone.'})
 binary=z.read('Payload/Spiderman.app/Spiderman')
 endpoint_paths=sorted({m.group().decode() for m in re.finditer(rb'/(?:PortalData|Validation|Inventory|Alliance|Leaderboard|common)/[A-Za-z0-9_]+\.php',binary)})
 write('network_paths.json',{'paths':endpoint_paths,'note':'Static endpoint references do not prove a request was made or that an offline operation fails.'})
 assert z.testzip() is None
assert sha(source.read_bytes())==before
write('integrity.json',{'source':source.name,'sha256':before,'source_unchanged':True,'static_only':True,'save_files_examined_or_modified':False})
print('Read-only audit completed:',archive_count,'asset archives;',len(active),'active portals;',len(expired),'expired portals;',len(duplicates),'duplicate suit groups;',len(missing),'missing texture references')
