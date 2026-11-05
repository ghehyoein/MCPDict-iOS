// New iOS implementation inspired by vearvip/mcpdict-frontend (MIT).
'use strict';
const tell = value => window.webkit?.messageHandlers?.mapEvent?.postMessage(value);
const empty = {version:8,sources:{},layers:[{id:'background',type:'background',paint:{'background-color':'#edf1f2'}}]};
const map = new maplibregl.Map({container:'map',style:empty,center:[108,34],zoom:3,maxZoom:18,attributionControl:false});
map.addControl(new maplibregl.NavigationControl({showCompass:false}),'top-right');
map.addControl(new maplibregl.AttributionControl({compact:false,customAttribution:'<a href="https://www.maptiler.com/copyright/">© MapTiler</a> <a href="https://www.openstreetmap.org/copyright">© OpenStreetMap contributors</a>'}));
let current = {points:[],key:'',fit:0};
let key = ''; let lastFit = 0; let popup;
const collection = () => ({type:'FeatureCollection',features:current.points.map(p=>({type:'Feature',geometry:{type:'Point',coordinates:[p.longitude,p.latitude]},properties:{id:p.id,name:p.name,color:p.color,reading:p.reading}}))});
function paint(){
  if(!map.isStyleLoaded()) return;
  const source = map.getSource('dialects');
  if(source) {source.setData(collection());return;}
  map.addSource('dialects',{type:'geojson',data:collection(),cluster:true,clusterRadius:36,clusterMaxZoom:14});
  map.addLayer({id:'clusters',type:'circle',source:'dialects',filter:['has','point_count'],paint:{'circle-color':'#007f86','circle-radius':18,'circle-stroke-color':'white','circle-stroke-width':2}});
  // Count labels require the style's glyph source; circles remain usable without a key.
  if(map.getStyle().glyphs) map.addLayer({id:'counts',type:'symbol',source:'dialects',filter:['has','point_count'],layout:{'text-field':['get','point_count_abbreviated'],'text-size':12},paint:{'text-color':'white'}});
  map.addLayer({id:'points',type:'circle',source:'dialects',filter:['!',['has','point_count']],paint:{'circle-color':['get','color'],'circle-radius':7,'circle-stroke-color':'white','circle-stroke-width':1.5}});
  if(map.getStyle().glyphs) map.addLayer({id:'names',type:'symbol',source:'dialects',minzoom:7,filter:['!',['has','point_count']],layout:{'text-field':['concat',['get','name'],'\n',['get','reading']],'text-size':12,'text-anchor':'top','text-offset':[0,1]},paint:{'text-color':'#202020','text-halo-color':'white','text-halo-width':2}});
}
function fit(){
  if(!current.points.length)return;
  const bounds = new maplibregl.LngLatBounds();
  current.points.forEach(p=>bounds.extend([p.longitude,p.latitude]));
  map.fitBounds(bounds,{padding:36,maxZoom:12,duration:500});
}
window.updateMap = payload => {
  current=payload;
  if(payload.key!==key){
    key=payload.key;
    tell({error:''});
    map.setStyle(key ? 'https://api.maptiler.com/maps/streets-v4/style.json?key='+encodeURIComponent(key) : empty);
  }else paint();
  if(payload.fit!==lastFit){lastFit=payload.fit;fit();}
};
map.on('style.load',paint);
map.on('error',()=>tell({error:'MapTiler 底圖未能完整載入，請檢查網路、API key、允許的 User-Agent 或服務額度；可在設定清除 key 改用系統地圖。'}));
map.on('click',async event=>{
  const layers=['clusters','points'].filter(id=>map.getLayer(id));
  if(!layers.length)return;
  const features=map.queryRenderedFeatures(event.point,{layers});
  if(!features.length)return;
  let list=features;
  const feature=features[0];
  if(feature.properties.cluster){
    const source=map.getSource('dialects');
    const leaves=await source.getClusterLeaves(feature.properties.cluster_id,10000,0);
    const coords=new Set(leaves.map(f=>f.geometry.coordinates.join(',')));
    if(coords.size>1 && map.getZoom()<17){
      const zoom=await source.getClusterExpansionZoom(feature.properties.cluster_id);
      map.easeTo({center:feature.geometry.coordinates,zoom:Math.min(zoom,18)});return;
    }
    list=leaves;
  }
  const container=document.createElement('div');
  const seen=new Set();
  list.forEach(f=>{
    if(seen.has(f.properties.id))return;seen.add(f.properties.id);
    const button=document.createElement('button');
    button.textContent=f.properties.name+(f.properties.reading?' · '+f.properties.reading:'');
    button.onclick=()=>tell({selected:f.properties.id});container.appendChild(button);
  });
  popup?.remove();popup=new maplibregl.Popup().setLngLat(event.lngLat).setDOMContent(container).addTo(map);
});
// Local diagnostic used by the WKWebView integration test; no key returned.
window.mapDiagnostic=()=>({loaded:map.isStyleLoaded(),points:map.getSource('dialects')?current.points.length:0});
