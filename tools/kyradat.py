"""Dump the EOB1 static tables of ScummVM's kyra.dat to JSON (ids from resource.h)."""
import re,struct,sys,json
resh=open(sys.argv[1]).read()
m=re.search(r'enum KyraResources \{(.*?)\n\};',resh,re.S)
names={}; n=0
for line in m.group(1).split('\n'):
    line=line.split('//')[0].strip().rstrip(',')
    if not line or line.startswith('#') or line.startswith('kLoadAll'): continue
    if '=' in line: name,val=[s.strip() for s in line.split('=')]; n=int(val)
    else: name=line; n+=1
    names[n]=name
d=open(sys.argv[2],'rb').read(); i=0; ents={}
while True:
    off=struct.unpack_from('<I',d,i)[0]
    if off==0: break
    j=d.index(b'\0',i+4); ents[d[i+4:j].decode('latin1')]=off; i=j+1
keys=sorted(ents,key=lambda k:ents[k])
def fdata(name):
    k=keys.index(name); o=ents[name]; e=ents[keys[k+1]] if k+1<len(keys) else len(d)
    return d[o:e]
idx=fdata('INDEX'); ver,ng=struct.unpack_from('>II',idx); defs=struct.unpack_from('>%dH'%ng,idx,8)
print('version',ver,'games',[hex(x) for x in defs])
out={}
for gd in defs:
    if gd>>12!=3: continue
    mp=fdata('0%01X%01X%01X000%01X'%(gd>>12&15,gd>>8&15,gd>>4&15,gd&15))
    num=struct.unpack_from('>H',mp)[0]; p=2; tabs={}
    for _ in range(num):
        rid,typ,fn=struct.unpack_from('>HBI',mp,p); p+=7
        raw=fdata('%08X'%fn)
        tabs[names.get(rid,str(rid))]={'type':typ,'data':list(raw)}
    out[hex(gd)]=tabs
    print(hex(gd),len(tabs))
json.dump(out,open(sys.argv[3],'w'))
