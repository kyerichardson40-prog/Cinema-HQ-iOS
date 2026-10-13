"""Add an independent AS3 controller to an existing native UI sprite.
Every original ABC, shape, font, texture, placement and animation byte is retained.
"""
import struct,zlib
from swf_read import header,tags,zstr

def tag(code,payload):
 return struct.pack('<H',code<<6|63)+struct.pack('<I',len(payload))+payload

def inject(raw,module,target,class_name):
 assert raw[:3]==b'GYV'
 b,start,rect,rate,frames=header(raw);mb,ms,*_=header(module)
 original=list(tags(b,start));compiled=list(tags(mb,ms))
 assert any(c==69 and struct.unpack_from('<I',v)[0]&8 for c,v,*_ in compiled)
 abcs=[v for c,v,*_ in compiled if c==82];assert len(abcs)==1
 classes=[]
 for c,v,*_ in compiled:
  if c==76:
   n=struct.unpack_from('<H',v)[0];p=2
   for _ in range(n):
    ident=struct.unpack_from('<H',v,p)[0];name,p=zstr(v,p+2);classes.append((ident,name))
 assert classes==[(0,class_name)],classes
 definitions={2,6,7,10,11,14,20,21,22,32,33,34,35,36,37,39,46,48,60,61,62,73,75,83,84,87,88,90,91}
 ids={struct.unpack_from('<H',v)[0] for c,v,*_ in original if c in definitions};new_id=max(ids)+1
 assert target in ids and new_id<65535
 empty_sprite=tag(39,struct.pack('<HH',new_id,1)+tag(1,b'')+tag(0,b''))
 inserted=changed=mapped=False;out=[]
 for c,v,at,pos in original:
  end=pos+len(v);chunk=b[at:end]
  if c==39 and not inserted:out.append(empty_sprite);inserted=True
  if c==39 and struct.unpack_from('<H',v)[0]==target:
   placements=list(tags(v,4));depths=[]
   for code,data,*_ in placements:
    if code==26:depths.append(struct.unpack_from('<H',data,1)[0])
    elif code==70:depths.append(struct.unpack_from('<H',data,2)[0])
   depth=max(depths)+1;assert depth<65535
   # PlaceObject2: character, identity matrix, name; no original clip is replaced.
   place=tag(26,b'\x26'+struct.pack('<HH',depth,new_id)+b'\x00SMUControls\0')
   replacement=bytearray(v[:4]);placed=False
   for code,data,a,p in placements:
    if code==1 and not placed:replacement+=place;placed=True
    replacement+=v[a:p+len(data)]
   assert placed;chunk=tag(39,replacement);changed=True
  elif c==76:
   assert not mapped
   count=struct.unpack_from('<H',v)[0]
   # Keep all of the game's existing class mappings exactly.
   payload=struct.pack('<H',count+1)+v[2:]+struct.pack('<H',new_id)+class_name.encode()+b'\0'
   out.append(tag(82,abcs[0]));chunk=tag(76,payload);mapped=True
  out.append(chunk)
 assert inserted and changed and mapped
 result=bytearray(b[:start]+b''.join(out));struct.pack_into('<I',result,4,len(result));newtags=list(tags(result,start))
 # Prove original actions/ABC, images, fonts and shape definitions are byte-identical.
 for code in [82]+sorted(definitions-{39}):
  old=[v for c,v,*_ in original if c==code];new=[v for c,v,*_ in newtags if c==code]
  assert new[:len(old)]==old,(code,'original asset/script changed')
 oldsprites={struct.unpack_from('<H',v)[0]:v for c,v,*_ in original if c==39}
 newsprites={struct.unpack_from('<H',v)[0]:v for c,v,*_ in newtags if c==39}
 for ident,data in oldsprites.items():
  if ident!=target:assert newsprites[ident]==data
 result[:3]=b'GYV';header(result)
 return bytes(result),{'class':class_name,'parent_sprite':target,'new_sprite':new_id,'depth':depth,'original_abc_unchanged':True,'original_artwork_and_animation_unchanged':True,'before_crc32':zlib.crc32(raw)&0xffffffff,'after_crc32':zlib.crc32(result)&0xffffffff}
