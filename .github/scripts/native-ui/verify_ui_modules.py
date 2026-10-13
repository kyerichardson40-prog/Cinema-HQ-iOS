import json,sys
from pathlib import Path
from swf_read import header,tags,zstr
from abc_read import Reader
root=Path(sys.argv[1]);proof=[]
for name,methods in [('SMUGameControls',['tick','drain']),('SMUHeaderControls',['inset'])]:
 raw=root.joinpath(name+'.swf').read_bytes();b,start,*_=header(raw);abcs=[]
 for code,v,*_ in tags(b,start):
  if code==82:
   abcname,p=zstr(v,4);abcs.append(Reader(v[p:]).parse())
 assert len(abcs)==1
 abc=abcs[0];classes=[abc.name(n) for n,*_ in abc.instances]
 assert classes==[name],('Built-in classes must remain external',classes)
 traits=abc.instances[0][-1];names=[abc.name(n) for n,*_ in traits]
 assert all(x in names for x in methods)
 proof.append({'module':name,'only_new_control_class_embedded':True,'existing_flash_runtime_reused':True,'methods':methods,'bytes':len(raw)})
(root/'module-verification.json').write_text(json.dumps(proof,indent=2));print('Native AS3 module verification passed')
