"""Extract option lists, orthography tables and IPA rewrite chains from Android source.
Usage: python tools/generate_reading_formats.py /path/to/osfans-MCPDict
"""
import json,re,sys,xml.etree.ElementTree as ET
from pathlib import Path
root=Path(sys.argv[1]); out=Path(__file__).resolve().parents[1]/'App'
res=root/'app/src/main/res'; tree=ET.parse(res/'values/strings.xml').getroot()
strings={e.attrib['name']:e.text or '' for e in tree.findall('string')}
arrays={e.attrib['name']:[strings[x.text[8:]] if (x.text or '').startswith('@string/') else x.text for x in e] for e in tree.findall('string-array')}
xml=ET.parse(res/'xml/preferences.xml').getroot(); android='{http://schemas.android.com/apk/res/android}'
spec=[]
for e in xml.iter():
 k=e.get(android+'key','').replace('@string/pref_key_','')
 if k not in ['mc_display','zyyy_display','mandarin_display','cantonese_romanization','minnan_display','dgy_display','vietnamese_tone_position','korean_display','japanese_display']:continue
 entries=arrays[e.get(android+'entries').split('/')[-1]];values=arrays[e.get(android+'entryValues').split('/')[-1]]
 default=e.get(android+'defaultValue');defaults=arrays[default.split('/')[-1]] if default.startswith('@array/') else [default]
 spec.append(dict(id=k,title=strings[e.get(android+'title').split('/')[-1]],multiple=e.tag=='MultiSelectListPreference',options=[dict(id=v,title=t) for v,t in zip(values,entries)],defaults=defaults))
data={'specs':spec,'tables':{},'rules':{}}
for p in (res/'raw').glob('orthography_*'):
 data['tables'][p.stem]=[line.split() for line in p.read_text().splitlines() if line.strip() and not line.startswith('#')]
for name in ['Mandarin','Korean','Vietnamese','Minnan']:
 text=(root/f'app/src/main/java/com/osfans/mcpdict/Orth/{name}.java').read_text()
 start=text.index('static String getIPA') if 'static String getIPA' in text else text.index('s = base;')
 body=text[start:];body=body[:body.index('return Orthography.formatTone') if 'return Orthography.formatTone' in body else body.index('return s;')]
 rules=[]
 for m in re.finditer(r'\.(replace|replaceFirst)\(("(?:[^"\\]|\\.)*"),\s*("(?:[^"\\]|\\.)*")\)',body):
  rules.append([m[1],json.loads(m[2]),json.loads(m[3])])
 data['rules'][name]=rules
(out/'ReadingFormatsData.json').write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
print('Generated',len(spec),'format groups')
