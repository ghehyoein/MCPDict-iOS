"""Bundle the pinned Android normalized TSV catalog and an offline query database."""
import hashlib, json, sqlite3, subprocess, sys
from pathlib import Path
import regex
from urllib.parse import quote

def build(checkout, output):
    checkout, output = Path(checkout).resolve(), Path(output)
    def git(*args):
        return subprocess.check_output(['git', '-c', 'safe.directory='+str(checkout), '-C', str(checkout), *args], text=True).strip()
    commit = git('rev-parse', 'HEAD')
    source = checkout/'tools/tables/output'
    details = json.loads((source/'_詳情.json').read_text(encoding='utf-8'))
    output.mkdir(parents=True, exist_ok=True)
    entries, total = [], 0
    db = sqlite3.connect(output/'bundled.db')
    db.executescript("CREATE VIRTUAL TABLE langs USING fts5(字組, 語言, 讀音, 註釋, tokenize='unicode61 remove_diacritics 0'); CREATE VIRTUAL TABLE info USING fts5(簡稱, 語言); CREATE VIRTUAL TABLE mcpdict USING fts5(漢字);")
    for file in sorted(source.glob('*.tsv')):
        name = file.stem
        if name not in details or not file.stat().st_size: continue
        raw = file.read_bytes()
        blob = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
        expected = git('rev-parse', 'HEAD:tools/tables/output/'+file.name)
        if expected != blob:
            raw = subprocess.check_output(['git','-c','safe.directory='+str(checkout),'-C',str(checkout),'show','HEAD:tools/tables/output/'+file.name])
            blob = hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
        assert expected == blob, file.name
        meta = {k: (v if isinstance(v,str) else json.dumps(v,ensure_ascii=False,separators=(',',':'))) for k,v in details[name].items()}
        source_name = meta.get('文件名', '')
        if source_name and (checkout/'tools/tables/data'/source_name).is_file():
            meta['文件網址'] = 'https://github.com/osfans/MCPDict/blob/'+commit+'/tools/tables/data/'+quote(source_name)
        def path(key): return [v.strip() for v in meta.get(key,'').split('－') if v.strip()] or ['未分類']
        identity = hashlib.sha256(name.encode()).hexdigest()[:24]
        rows=[]
        for line in raw.decode('utf-8').split('\n'):
            line = line.removesuffix('\r')
            if not line or line.startswith('#'): continue
            fields=line.split('\t')
            if len(fields)<2 or not fields[0] or not fields[1]: raise ValueError('Invalid TSV '+file.name)
            chars=' '.join(c for c in regex.findall(r'\X',fields[0]) if not c.isspace())
            rows.append((chars,name,fields[1],'\t'.join(fields[2:])))
        if not rows: raise ValueError('Empty table '+file.name)
        db.executemany('INSERT INTO langs VALUES (?,?,?,?)',rows)
        db.execute('INSERT INTO info VALUES (?,?)',(name,meta.get('語言',name)))
        (output/(identity+'.tsv')).write_bytes(raw)
        entry=dict(id=identity,name=name,fullName=meta.get('語言',name),atlas=path('地圖集二分區'),dictionary=path('音典分區'),administrative=[meta[k] for k in ['省','市','縣','鎮','村','自然村'] if meta.get(k)] or ['未標註行政區'],source=meta.get('字表來源',''),sourceCommit=commit,recordCount=len(rows),size=len(raw),sha256=hashlib.sha256(('tsv-v1:'+blob).encode()).hexdigest(),url='https://raw.githubusercontent.com/osfans/MCPDict/'+commit+'/tools/tables/output/'+file.name,metadata=meta,atlasColor=meta.get('地圖集二顏色',''),dictionaryColor=meta.get('音典顏色',''),format='upstream-tsv-v1',gitBlob=blob)
        try:
            lon,lat=map(float,meta.get('經緯度','').replace('，',',').split(','))
            if -180<=lon<=180 and -90<=lat<=90: entry['location']=dict(longitude=lon,latitude=lat)
        except ValueError: pass
        entries.append(entry); total+=len(rows)
    db.commit()
    assert db.execute('PRAGMA quick_check').fetchone()[0]=='ok'
    assert db.execute('SELECT count(*) FROM langs').fetchone()[0]==total
    assert db.execute("SELECT count(*) FROM langs WHERE langs MATCH '字組 : 中'").fetchone()[0]>0
    db.close()
    catalog=dict(schemaVersion=1,version=commit,sourceRepository='https://github.com/osfans/MCPDict',sourceCommit=commit,scope='內置完整字表快照',tables=entries)
    (output/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False),encoding='utf-8')
    report=dict(sourceCommit=commit,tables=len(entries),readings=total,databaseBytes=(output/'bundled.db').stat().st_size,databaseSHA256=hashlib.sha256((output/'bundled.db').read_bytes()).hexdigest())
    (output/'bundle-report.json').write_text(json.dumps(report),encoding='utf-8')
    print(json.dumps(report),flush=True)
    return report

if __name__=='__main__': build(sys.argv[1],sys.argv[2])
