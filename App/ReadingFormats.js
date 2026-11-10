// Port of osfans/MCPDict Orth/*.java. Data and rewrite chains are extracted
// by tools/generate_reading_formats.py; no network or executable user input.
function rewrite(s, name) {
  for (const [kind,a,b] of FORMAT_DATA.rules[name]) {
    s = kind === 'replace' ? s.split(a).join(b) : s.replace(new RegExp(a), b.replace(/\$0/g,'$&'));
  }
  return s;
}
const roman = text => ({text, tone:false, italic:true});
const ipa = (text,tone='') => ({text:text+(tone==='_'?'':tone),tone:true,italic:false});
const plain = text => ({text,tone:false,italic:false});
const rows = key => FORMAT_DATA.tables['orthography_'+key];
function bidirectional(key) {
  const map={};for(const r of rows(key)){map[r[0]]=r[1]+r[2];map[r[1]+r[2]]=r[0];}return map;
}
const pinyin=bidirectional('pu_pinyin'), vietnamese=bidirectional('vn');
function mandarin(s, system) {
  let tone=/[1-4]$/.test(s)?s.slice(-1):'_';if(tone!=='_')s=s.slice(0,-1);
  if(system===0)return ipa(rewrite(s,'Mandarin'),tone);
  if(system===1){
    s=s.replace(/ea/g,'ê');let pos=-1;
    if(s.endsWith('iu'))pos=s.length-1;else for(const c of 'aoeêiuvnm'){pos=s.indexOf(c);if(pos>=0)break;}
    if(pos<0)return null;
    return roman(Array.from(s).map((c,i)=>{const t=i===pos?tone:'_';return pinyin[c+t] || c+(t==='_'?'':pinyin['_'+t]||'');}).join(''));
  }
  const partial={},whole={},tones={};
  for(const r of rows('pu_bopomofo')){if('234_'.includes(r[1]))tones[r[1]]=r[0];else{partial[r[1]]=r[0];if(r[2])whole[r[2]]=r[0];}}
  if(whole[s])s=whole[s];else{
    s=s.replace(/^([jqx])u/,'$1v');let p=Math.min(2,s.length);while(p>0&&!partial[s.slice(0,p)])p--;
    if(!p||!partial[s.slice(p)])return null;s=partial[s.slice(0,p)]+partial[s.slice(p)];
  }
  return plain(tone==='_'?(tones[tone]||'')+s:s+(tones[tone]||''));
}
function cantonese(s,system,reverse=false){
  if(system===1)return reverse?s:roman(s);
  const index=system===0?4:system-1;
  const initials={},finals={};
  for(const r of rows('ct_initials'))initials[r[reverse?index:0]]=r[reverse?0:index];
  for(const r of rows('ct_finals'))finals[r[reverse?index:0]]=r[reverse?0:index];
  let tone=(reverse?/[1-9]$/:/[1-6]$/).test(s)?s.slice(-1):'_';if(tone!=='_')s=s.slice(0,-1);
  let p=0;while(p<s.length&&!finals[s.slice(p)])p++;if(p===s.length)return null;
  let fin=finals[s.slice(p)],init=p===0?'':initials[s.slice(0,p)];if(init===undefined)return null;
  if(reverse){tone=({'7':'1','8':'3','9':'6'})[tone]||tone;if(system===3&&!init&&fin.startsWith('yu'))init='j';return init+fin+(tone==='_'?'':tone);}
  if((system===0||system===2)&&/[ptk]$/.test(fin))tone=({'1':'7','3':'8','6':'9'})[tone]||tone;
  if(system===3&&init==='y'&&fin.startsWith('yu'))init='';
  return system===0?ipa(init+fin,tone):roman(init+fin+(tone==='_'?'':tone));
}
function japanese(s,system){
  if(system===3)return roman(s);const map={};for(const r of rows('jp'))for(let i=0;i<4;i++)map[r[i]]=r[system===0?4:system===1?0:system===2?1:3];
  let result='',p=0;while(p<s.length){let q=p;for(let n=4;n>0;n--)if(p+n<=s.length&&map[s.slice(p,p+n)]){q=p+n;result+=map[s.slice(p,q)];break;}if(q===p)return null;p=q;}
  return system===4?roman(result):plain(result);
}
function korean(s,system){
  if(system===0)return plain(rewrite(s,'Korean'));if(system===2)return roman(s);
  const ini=['g','kk','n','d','tt','r','m','b','pp','s','ss','','j','jj','ch','k','t','p','h'];
  const vow=['a','ae','ya','yae','eo','e','yeo','ye','o','wa','wae','oe','yo','u','wo','we','wi','yu','eu','ui','i'];
  const fin=['','k','kk0','ks0','n','nj0','nh0','d0','l','lg0','lm0','lb0','ls0','lt0','lp0','lh0','m','p','bs0','s0','ss0','ng','j0','ch0','k0','t0','p0','h0'];
  let p=0,q=s.length;for(let i=2;i>0;i--)if(i<=s.length&&ini.includes(s.slice(0,i))){p=i;break;}
  for(let i=s.length-2;i<s.length;i++)if(i>=p&&fin.includes(s.slice(i))){q=i;break;}
  const x=ini.indexOf(s.slice(0,p)),y=vow.indexOf(s.slice(p,q)),z=fin.indexOf(s.slice(q));
  return x<0||y<0||z<0?null:plain(String.fromCharCode(0xAC00+(x*21+y)*28+z));
}
function vietnam(s,system){
  let tone=/[rsfxj]$/.test(s)?s.slice(-1):'_';if(tone!=='_')s=s.slice(0,-1);
  if(system===0){const entering=/[ptc]$|ch$/.test(s);return ipa(rewrite(s,'Vietnamese'),String(entering?(tone==='s'?7:8):'_frxsj'.indexOf(tone)+1));}
  let text='',p=0;while(p<s.length){const key=s.slice(p,p+2);if(key.length===2&&vietnamese[key+'_']){
    if(key==='dd'||s.startsWith('uwow',p))text+=vietnamese[key+'_'];else{text+=vietnamese[key+tone];tone='_';}p+=2;
  }else{text+=s[p++];}}
  if(tone==='_')return plain(text);p=0;while(p<text.length&&!/[aeiouy]/.test(text[p]))p++;if(p===text.length)return null;
  let q=p+1;while(q<text.length&&/[aeiouy]/.test(text[q]))q++;
  if(q-p===3||q-p===2&&(q<text.length||s.startsWith('gi')||s.startsWith('qu')||system===2&&['oa','oe','uy'].includes(text.slice(p,q))))p++;
  return plain(text.slice(0,p)+(vietnamese[text[p]+tone]||text[p])+text.slice(p+1));
}
function formatOne(s,key,system){
  switch(key){case 'mandarin_display':return mandarin(s,system);case 'cantonese_romanization':return cantonese(s,system);
    case 'japanese_display':return japanese(s,system);case 'korean_display':return korean(s,system);case 'vietnamese_tone_position':return vietnam(s,system);
    case 'minnan_display':if(system===1)return roman(s);const tone=/[1-8]$/.test(s)?s.slice(-1):'0';return ipa(rewrite(tone==='0'?s:s.slice(0,-1),'Minnan'),tone);
  }
  return null;
}
function readingFormat(raw,key,selected){
  const spec=FORMAT_DATA.specs.find(x=>x.id===key);if(!spec)return null;
  const choices=spec.options.filter(x=>selected.includes(x.id));
  if(spec.multiple){
    // Composite upstream records carry precomputed reconstructions separated by '/'.
    const brace=raw.indexOf('{'),body=brace<0?raw:raw.slice(0,brace),suffix=brace<0?'':raw.slice(brace);
    const fields=body.split('/');if(fields.length<spec.options.length)return null;
    const result=[];
    if(key==='mc_display'){
      const tone=({'平':'1','上':'2','去':'3','入':'4'})[fields[18].slice(-1)]||'1';
      const py=choices.filter(x=>+x.id<100).length,ipaCount=choices.filter(x=>+x.id>=100&&+x.id<200).length,desc=choices.filter(x=>+x.id>=200),books=choices.filter(x=>+x.id>=300&&+x.id<400).length;
      for(const option of choices.filter(x=>+x.id<200)){
        const j=spec.options.indexOf(option);result.push(+option.id<100?roman(fields[j]):ipa(fields[j],tone));
        if((+option.id<100?py:ipaCount)>1)result.push(plain('('+option.title.replace('切韻拼音','切拼').replace(/轉寫|羅馬字|擬音/g,'')+')'));
        result.push(plain(' '));
      }
      if(py+ipaCount>0&&desc.length)result.push(plain('('));
      for(let i=0;i<desc.length;i++){const o=desc[i];result.push(plain((books>1?(o.id==='300'?'廣韻':o.id==='301'?'平水':''):'')+fields[spec.options.indexOf(o)]+(i===desc.length-1?'':' ')));}
      if(py+ipaCount>0&&desc.length)result.push(plain(')'));
    }else for(const option of choices){
      const s=fields[spec.options.indexOf(option)];
      if(key==='dgy_display'&&option.id==='1'&&choices.length>1)result.push(plain('('));
      result.push(ipa(s.slice(0,-1),s.slice(-1)));
      if(key==='dgy_display'&&option.id==='1'&&choices.length>1)result.push(plain(')'));
      if(key==='zyyy_display'&&choices.length>1)result.push(plain('('+option.title+')'));
      result.push(plain(' '));
    }
    if(suffix)result.push(plain(suffix));return result;
  }
  const result=[];
  for (const option of choices) {
    if(result.length)result.push(plain(' / '));
    const regex=/[\p{L}\p{N}\p{M}\p{Sk}_]+/gu;let cursor=0,match;
    while((match=regex.exec(raw))!==null){if(match.index>cursor)result.push(plain(raw.slice(cursor,match.index)));result.push(formatOne(match[0],key,+option.id)||plain(match[0]));cursor=regex.lastIndex;}
    if(cursor<raw.length)result.push(plain(raw.slice(cursor)));
  }
  return result;
}
function canonicalCantonese(input,system){
  return input.replace(/[\p{L}\p{N}\p{M}\p{Sk}_]+/gu,s=>cantonese(s,system,true)||s);
}
