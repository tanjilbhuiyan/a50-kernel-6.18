import re,sys
def load(p):
    d={}; name=None
    for l in open(p,errors='replace'):
        m=re.match(r"numid=(\d+),iface=\w+,name='(.*)'",l)
        if m: name=m.group(2); d[name]=None; continue
        m=re.match(r"\s*: values=(.*)",l)
        if m and name is not None: d[name]=m.group(1)
    return d
a,b=load(sys.argv[1]),load(sys.argv[2])
ch=[(n,a[n],b.get(n)) for n in a if a[n]!=b.get(n)]
print("controls: %d vs %d, changed: %d"%(len(a),len(b),len(ch)))
for n,x,y in ch: print("  %-45s %s -> %s"%(n,x,y))
