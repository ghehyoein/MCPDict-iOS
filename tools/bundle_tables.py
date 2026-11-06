"""Bundle the pinned Android normalized TSV catalog and an offline query database."""
import hashlib, json, sqlite3, subprocess, sys
from pathlib import Path
import regex
from urllib.parse import quote

def build_references(checkout, output):
    """Build a separate read-only index from the same normalized sources as Android DB.getUnicode."""
    from collections import defaultdict
    import re
    books = "說文 集韻 康熙 匯纂 漢大".split()
    fields = "異體字 字形變體 字形描述 部件檢索 兩分 總筆畫數 部首餘筆 五筆畫 五筆86 五筆98 五筆06 倉頡三代 倉頡五代 倉頡六代 山人".split()
    with sqlite3.connect(output/'references.db') as db:
        db.executescript("CREATE TABLE entries(hz TEXT, field TEXT, value TEXT, PRIMARY KEY(hz,field)) WITHOUT ROWID; CREATE TABLE ranges(lo INTEGER, hi INTEGER, label TEXT);")
        # Use HanZi.getUnicodeExt ranges from the pinned Android version, including supplementary planes.
        java = (checkout/'app/src/main/java/com/osfans/mcpdict/Orth/HanZi.java').read_text('utf-8')
        ranges = re.findall(r'if \(unicode (?:>= (0x\w+) && unicode <= (0x\w+)|== (0x\w+))\) ext = "([^"]+)"', java)
        if not ranges: raise ValueError("Android Unicode ranges unavailable")
        db.executemany("INSERT INTO ranges VALUES(?,?,?)", ((int(a or c,16),int(b or c,16),v) for a,b,c,v in ranges))
        for field in books + fields:
            entries = defaultdict(list)
            with (checkout/'tools/tables/output'/(field+'.tsv')).open(encoding='utf-8') as f:
                for line in f:
                    if line.startswith('#') or not line.strip(): continue
                    hz, value = line.rstrip('\r\n').split('\t', 1)
                    value = value.rstrip('\t').replace('\t','\n')
                    if field in ('字形描述','部件檢索'):
                        value = value.replace('UCS2003','2003').translate(str.maketrans('GHMTJKPVUSB','陸港澳臺日韓朝越統大英')).replace('2003','UCS2003').replace(' ','')
                    if field not in books: value = value.replace(',',' ')
                    if value and value not in entries[hz]: entries[hz].append(value)
            sep = '\n\n' if field in books else ' '
            db.executemany("INSERT INTO entries VALUES(?,?,?)", ((hz,field,sep.join(values)) for hz,values in entries.items()))
        assert db.execute("SELECT count(*) FROM entries WHERE hz='一'").fetchone()[0] == len(books+fields)
        assert db.execute("PRAGMA quick_check").fetchone()[0] == 'ok'

def build(checkout, output):
    checkout, output = Path(checkout).resolve(), Path(output)
    def git(*args):
        return subprocess.check_output(['git', '-c', 'safe.directory='+str(checkout), '-C', str(checkout), *args], text=True).strip()
    commit = git('rev-parse', 'HEAD')
    source = checkout/'tools/tables/output'
    details = json.loads((source/'_詳情.json').read_text(encoding='utf-8'))
    output.mkdir(parents=True, exist_ok=True)
    entries, total = [], 0
    build_references(checkout, output)
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
