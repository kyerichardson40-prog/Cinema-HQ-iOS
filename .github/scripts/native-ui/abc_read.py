import struct
class Reader:
 def __init__(self,b):self.b=b;self.p=0
 def u8(self):x=self.b[self.p];self.p+=1;return x
 def u16(self):x=struct.unpack_from('<H',self.b,self.p)[0];self.p+=2;return x
 def u30(self):
  v=s=0
  for _ in range(5):
   x=self.u8();v|=(x&127)<<s
   if not x&128:break
   s+=7
  return v
 def bytes(self,n):v=self.b[self.p:self.p+n];self.p+=n;return v
 def pool(self,fn):return [None]+[fn() for _ in range(max(0,self.u30()-1))]
 def traits(self):
  a=[]
  for _ in range(self.u30()):
   n=self.u30();k=self.u8();t=k&15;v=[self.u30(),self.u30()]
   if t in [0,6]:
    x=self.u30();v.append(x)
    if x:v.append(self.u8())
   if k&64:v.append([self.u30() for _ in range(self.u30())])
   a.append((n,k,v))
  return a
 def parse(self):
  self.version=(self.u16(),self.u16());self.ints=self.pool(self.u30);self.uints=self.pool(self.u30);self.doubles=self.pool(lambda:struct.unpack('<d',self.bytes(8))[0]);self.strings=self.pool(lambda:self.bytes(self.u30()).decode('utf8','replace'));self.ns=self.pool(lambda:(self.u8(),self.u30()));self.nss=self.pool(lambda:[self.u30() for _ in range(self.u30())]);self.mn=[None]
  for _ in range(max(0,self.u30()-1)):
   k=self.u8();v=[]
   if k in [7,13,9,14]:v=[self.u30(),self.u30()]
   elif k in [15,16,27,28]:v=[self.u30()]
   elif k in [17,18]:pass
   elif k==29:v=[self.u30()]+[self.u30() for _ in range(self.u30())]
   else:raise Exception(('multiname',k,self.p))
   self.mn.append((k,v))
  self.methods=[]
  for _ in range(self.u30()):
   count=self.u30();ret=self.u30();params=[self.u30() for _ in range(count)];name=self.u30();f=self.u8();opts=[];names=[]
   if f&8:opts=[(self.u30(),self.u8()) for _ in range(self.u30())]
   if f&128:names=[self.u30() for _ in range(count)]
   self.methods.append((name,ret,params,f,opts,names))
  for _ in range(self.u30()):
   name=self.u30();n=self.u30();[self.u30() for _ in range(n*2)]
  count=self.u30();self.instances=[]
  for _ in range(count):
   n=self.u30();sup=self.u30();f=self.u8();protected=self.u30() if f&8 else None;interfaces=[self.u30() for _ in range(self.u30())];init=self.u30();ts=self.traits();self.instances.append((n,sup,f,init,ts))
  self.classes=[]
  for _ in range(count):self.classes.append((self.u30(),self.traits()))
  self.scripts=[]
  for _ in range(self.u30()):self.scripts.append((self.u30(),self.traits()))
  self.bodies={}
  for _ in range(self.u30()):
   id=self.u30();m=[self.u30() for _ in range(4)];code=self.bytes(self.u30());exc=[[self.u30() for _ in range(5)] for _ in range(self.u30())];ts=self.traits();self.bodies[id]=(m,code,exc,ts)
  assert self.p==len(self.b),(self.p,len(self.b))
  return self
 def name(self,n):
  if not n:return '*'
  k,v=self.mn[n]
  if k in [7,13]:return self.strings[v[1]]
  if k in [9,14]:return self.strings[v[0]]
  return str((k,v))
if __name__=='__main__':
 from pathlib import Path
 import sys
 for file in sys.argv[1:]:
  r=Reader(Path(file).read_bytes()).parse()
  for n,s,f,init,ts in r.instances:
   name=r.name(n)
   if any(k in name.lower() for k in ['mainhud','pausemenu','gameplay','topbardoc','topbarcomplete']):
    print(name,'extends',r.name(s),'flags',f,'ctor',init);print([(r.name(n),k,v) for n,k,v in ts])
