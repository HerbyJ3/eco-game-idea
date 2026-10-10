import re,glob,sys,collections
rows=collections.defaultdict(dict)
for f in sorted(glob.glob('/tmp/claude-0/exp/*_*.txt')):
    name,seed=f.split('/')[-1][:-4].rsplit('_',1)
    txt=open(f).read()
    if 'RESULT' not in txt: continue
    tab=[l.split() for l in txt.splitlines() if re.match(r'^\s*\d+\s+\d+\s+\d+\s+\d+\s+\d+/',l)]
    final=int(tab[-1][1]); dead=tab[-1][4].split('/')
    firstdry=next((int(r[0]) for r in tab if float(r[7])==0.0),None)
    firstthirst=next((int(r[0]) for r in tab if int(r[4].split('/')[1])>0),None)
    peak=max(int(r[1]) for r in tab)
    t3=re.search(r'first_birth_sol (\S+)',txt).group(1).rstrip(',')
    births=re.search(r'T3 \w+ births (\d+)',txt).group(1)
    t5=re.search(r'T5 (\w+)',txt).group(1)
    air=re.search(r'turn_backs_air (\d+)',txt).group(1)
    st=re.search(r'first settlement sol (\S+)',txt).group(1)
    rows[name][seed]=dict(final=final,peak=peak,thirst=int(dead[1]),air=int(dead[0]),eva=int(dead[4]),dry=firstdry,fthirst=firstthirst,fb=t3,births=births,t5=t5,airtb=air,settle=st)
seeds=['42','7','99','1234','2026']
for n in sorted(rows):
    print(f'== {n}')
    for s in seeds:
        r=rows[n].get(s)
        if r: print(f"  {s:>5} final {r['final']:4} peak {r['peak']:4} births {r['births']:>4} firstBirth {r['fb']:>5} thirstDeaths {r['thirst']:3} firstThirst {str(r['fthirst']):>5} firstDry {str(r['dry']):>5} air {r['air']} eva {r['eva']} airTB {r['airtb']} T5 {r['t5']} settle {r['settle']}")
    alive=sum(1 for s in seeds if s in rows[n] and rows[n][s]['final']>0)
    print(f'  alive at 1500: {alive}/{sum(1 for s in seeds if s in rows[n])}')
