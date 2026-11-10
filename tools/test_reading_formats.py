import json,shutil,subprocess,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
@unittest.skipUnless(shutil.which('node'), 'Node.js is needed for the JavaScript port checks')
class ReadingFormatsTests(unittest.TestCase):
 def test_android_conversion_samples_and_input_roundtrips(self):
  script=r'''
const fs=require('fs'), vm=require('vm'), assert=require('assert');
const c={FORMAT_DATA:JSON.parse(fs.readFileSync('App/ReadingFormatsData.json','utf8'))};vm.createContext(c);vm.runInContext(fs.readFileSync('App/ReadingFormats.js','utf8'),c);
const render=(s,k,o)=>c.readingFormat(s,k,[String(o)]).map(x=>x.text).join('');
assert.equal(render('xing1','mandarin_display',0),'ɕiŋ1');
assert.equal(render('xing1','mandarin_display',1),'xīng');
assert.equal(render('xing1','mandarin_display',2),'ㄒㄧㄥ');
assert.equal(c.readingFormat('xing1','mandarin_display',['0','1','2']).map(x=>x.text).join(''),'ɕiŋ1 / xīng / ㄒㄧㄥ');
assert.equal(c.readingFormat('xing1','mandarin_display',[]).length,0);
assert.equal(render('nhaats','vietnamese_tone_position',1),'nhất');
assert.equal(render('hoaf','vietnamese_tone_position',1),'hòa');
assert.equal(render('hoaf','vietnamese_tone_position',2),'hoà');
assert.equal(render('il','korean_display',1),'일');
assert.equal(render('itu','japanese_display',1),'いつ');
assert.equal(render('itu','japanese_display',2),'イツ');
assert.equal(render('itu','japanese_display',4),'itsu');
assert.equal(render('it4','minnan_display',0),'it4');
for(const input of ['ling4','jyut6','jat1','si3'])for(let i=0;i<5;i++){
 const output=render(input,'cantonese_romanization',i);assert.equal(c.canonicalCantonese(output,i),input);
}
const mc='thomh/thomH/thomh/thomm/tʰɑ̆m/tʰɒm/tʰɑm/tʰᴀm/tʰɒm/tʰəm/tʰʌm/tʰəm/tʰəm/tʰəm/t̙ʰə̀m/tʰə̀m/tʰə̀m/tʰɔmh/透開一覃去/咸攝/咸開一去勘透/去聲53勘/去声28勘/他紺切';
for(const option of c.FORMAT_DATA.specs[0].options){assert.ok(c.readingFormat(mc,'mc_display',[option.id]).length>0);}
assert.equal(render(mc,'mc_display',400),'他紺切');
'''
  result=subprocess.run(['node','-e',script],cwd=ROOT,capture_output=True,text=True)
  self.assertEqual(result.returncode,0,result.stderr)
