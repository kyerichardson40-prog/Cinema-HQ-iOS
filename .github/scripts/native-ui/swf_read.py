import struct,zlib
from pathlib import Path
class Bits:
 def __init__(self,b,bit=0):self.b=b;self.bit=bit
 def u(self,n):
  v=0
  for _ in range(n):v=v*2+((self.b[self.bit//8]>>(7-self.bit%8))&1);self.bit+=1
  return v
 def s(self,n):
  v=self.u(n);return v-(1<<n) if v&(1<<(n-1)) else v
 def pos(self):return (self.bit+7)//8

def header(b):
 if b[:3]==b'CWS':b=b'FWS'+b[3:8]+zlib.decompress(b[8:])
 assert b[:3] in (b'FWS',b'GYV');assert len(b)==struct.unpack_from('<I',b,4)[0]
 q=Bits(b,64);n=q.u(5);rect=[q.s(n) for _ in range(4)];p=q.pos();rate,frames=struct.unpack_from('<HH',b,p)
 return b,p+4,rect,rate/256,frames

def tags(b,start,end=None):
 end=len(b) if end is None else end;p=start
 while p<end:
  at=p;v=struct.unpack_from('<H',b,p)[0];p+=2;c,n=v>>6,v&63
  if n==63:n=struct.unpack_from('<I',b,p)[0];p+=4
  assert p+n<=end,(c,p,n,end)
  yield c,b[p:p+n],at,p;p+=n
 assert p==end

def walk(b,start,prefix=''):
 for c,v,at,pos in tags(b,start):
  yield c,v,at,pos,prefix
  if c==39:
   ident,frames=struct.unpack_from('<HH',v);yield from walk(v,4,prefix+str(ident)+'/')

def zstr(b,p):
 e=b.index(0,p);return b[p:e].decode('utf8','replace'),e+1
names={0:'End',4:'NextFrame',5:'PreviousFrame',6:'Play',7:'Stop',0x17:'Pop',0x1c:'GetVariable',0x1d:'SetVariable',0x3c:'DefineLocal',0x3d:'CallFunction',0x3e:'Return',0x40:'NewObject',0x41:'DefineLocal2',0x47:'Add2',0x48:'Less2',0x49:'Equals2',0x4e:'GetMember',0x4f:'SetMember',0x52:'CallMethod',0x53:'NewMethod',0x87:'StoreRegister',0x88:'ConstantPool',0x8e:'DefineFunction2',0x96:'Push',0x99:'Jump',0x9b:'DefineFunction',0x9d:'If'}
def actions(b,p=0,pool=None,indent='',out=None):
 if out is None:out=[]
 pool=[] if pool is None else pool
 while p<len(b):
  at=p;c=b[p];p+=1;n=0
  if c>=128:n=struct.unpack_from('<H',b,p)[0];p+=2
  v=b[p:p+n];p+=n;arg=''
  if c==0x88:
   count=struct.unpack_from('<H',v)[0];q=2;pool=[]
   for _ in range(count):s,q=zstr(v,q);pool.append(s)
   arg=repr(pool)
  elif c==0x96:
   q=0;args=[]
   while q<len(v):
    t=v[q];q+=1
    if t==0:a,q=zstr(v,q)
    elif t==1:a=struct.unpack_from('<f',v,q)[0];q+=4
    elif t==2:a='null'
    elif t==3:a='undefined'
    elif t==4:a='r'+str(v[q]);q+=1
    elif t==5:a=bool(v[q]);q+=1
    elif t==6:a=struct.unpack('<d',v[q+4:q+8]+v[q:q+4])[0];q+=8
    elif t==7:a=struct.unpack_from('<i',v,q)[0];q+=4
    elif t in (8,9):i=v[q] if t==8 else struct.unpack_from('<H',v,q)[0];q+=1 if t==8 else 2;a=pool[i] if i<len(pool) else 'const'+str(i)
    else:raise ValueError(('Push type',t))
    args.append(a)
   arg=repr(args)
  elif c in (0x99,0x9d):arg=f'->{p+struct.unpack_from("<h",v)[0]:x}'
  elif c==0x87:arg=str(v[0])
  elif c in (0x8e,0x9b):
   name,q=zstr(v,0);count=struct.unpack_from('<H',v,q)[0];q+=2;params=[]
   if c==0x8e:regs=v[q];flags=struct.unpack_from('<H',v,q+1)[0];q+=3;arg=f'regs={regs} flags={flags:x} '
   for _ in range(count):
    reg=None
    if c==0x8e:reg=v[q];q+=1
    s,q=zstr(v,q);params.append((reg,s))
   size=struct.unpack_from('<H',v,q)[0]
   out.append(f'{indent}{at:04x}: {names[c]} {name}{params} {arg}')
   actions(b[p:p+size],pool=pool,indent=indent+'  ',out=out);p+=size;continue
  elif v:arg=v.hex()
  out.append(f'{indent}{at:04x}: {names.get(c,hex(c))} {arg}')
  if c==0:break
 return out
if __name__=='__main__':
 import sys,collections
 for file in sys.argv[1:]:
  b,start,rect,rate,frames=header(Path(file).read_bytes());print(file,rect,rate,frames,collections.Counter(c for c,*_ in walk(b,start)))
  lines=[]
  for c,v,at,pos,prefix in walk(b,start):
   if c in (12,59):
    try:lines+= [f'TAG {c} at {at:x} prefix {prefix}']+actions(v,2 if c==59 else 0)
    except Exception as e:lines.append('Error '+repr(e))
  Path(file+'.actions.txt').write_text('\n'.join(lines))
