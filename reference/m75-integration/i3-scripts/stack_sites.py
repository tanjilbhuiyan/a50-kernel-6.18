from pathlib import Path
import os,struct,json
print('UPTIME',Path('/proc/uptime').read_text().strip())
processes={}
for p in Path('/proc').iterdir():
 if not p.name.isdigit():continue
 try:
  status=dict(x.split(':',1) for x in (p/'status').read_text().splitlines() if ':' in x)
  processes[int(p.name)]={'ppid':int(status['PPid']),'name':status['Name'].strip(),'threads':int(status['Threads']),'exe':os.readlink(p/'exe')}
 except (OSError,KeyError):pass
roots=[pid for pid,d in processes.items() if d['exe']=='/usr/bin/lomiri-telephony-service-handler']
for pid in roots:
 print('\nHANDLER',pid,json.dumps(processes[pid]))
 descendants=[c for c,d in processes.items() if d['ppid']==pid]
 print('DIRECT_CHILDREN',json.dumps({c:processes[c] for c in descendants}))
 for current in [pid]+descendants:
  p=Path('/proc')/str(current)
  try:
   print('PROCESS',current,'wchan',(p/'wchan').read_text().strip())
   call=(p/'syscall').read_text().split();print('SYSCALL',' '.join(call))
   mappings=[]
   for line in (p/'maps').read_text().splitlines():
    f=line.split(maxsplit=5);low,high=[int(x,16) for x in f[0].split('-')];mappings.append((low,high,f[1],int(f[2],16),f[5] if len(f)>5 else ''))
   if call[0]=='running':continue
   sp=int(call[-2],0)
   region=next(m for m in mappings if m[0]<=sp<m[1])
   size=min(16384,region[1]-sp)
   with (p/'mem').open('rb',buffering=0) as memory:
    memory.seek(sp);data=memory.read(size)
   print('RETURN_SITE_CANDIDATES (not an unwound backtrace)')
   count=0
   for i in range(0,len(data)-7,8):
    raw=struct.unpack_from('<Q',data,i)[0];address=raw&((1<<48)-1)
    for low,high,permissions,offset,name in mappings:
     if 'x' in permissions and low<=address<high:
      print(json.dumps({'stack_offset':hex(i),'address':hex(address),'file_offset':hex(address-low+offset),'file':name,'pac_stripped':raw!=address}));count+=1;break
    if count>=48:break
  except (OSError,ValueError,StopIteration) as error:print('UNVERIFIED',str(error))
