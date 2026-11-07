'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const base=fs.readFileSync('iptv-plus/iptv-plus-v1.2.1-auto-refresh.js','utf8');
const preview=fs.readFileSync('iptv-plus/iptv-plus-v1.2.2-hierarchy-preview.js','utf8');
new vm.Script(preview,{filename:'iptv-plus-v1.2.2-hierarchy-preview.js'});
function between(src,from,to){
 const a=src.indexOf(from),b=src.indexOf(to,a+from.length);
 assert.ok(a>=0&&b>a,'Missing source markers: '+from);
 return src.slice(a,b);
}
assert.equal(between(preview,'function channelKey(', 'function legacyChannelKey('),
             between(base,'function channelKey(', 'function legacyChannelKey('));
assert.equal(between(preview,'function favoriteIds(', 'function favoriteLookup('),
             between(base,'function favoriteIds(', 'function favoriteLookup('));
const helper=between(preview,'var IPTV_COUNTRIES=', 'function rememberGuideName(');
const context={text:v=>v==null?'':String(v)};
vm.createContext(context);
vm.runInContext(helper,context);
const fixtures=[
 [{id:'1Plus1.ua@HD',group:'Украина / Основные'},'UA','main'],
 [{id:'Suspilne.ua@SD',group:'Україна / Новини'},'UA','news'],
 [{id:'ChannelOne.ru@SD',group:'Россия / Основные'},'RU','main'],
 [{id:'NTV.ru@HD',group:'Россия / Кино и сериалы'},'RU','movies'],
 [{id:'Russia1.ru@SD',group:'Россия / Новости'},'RU','news'],
 [{id:'UkraineTv.ua@SD',group:'Музыка'},'UA','music'],
 [{id:'Unknown.intl',group:'Other / Sports'},'INTL','sports'],
 [{id:'ChannelOne.ru@SD',group:'Россия'},'RU','main'],
 [{id:'FirstPlus1.ru@SD',group:'Россия / Остальные'},'RU','other'],
 [{id:'Unknown',group:'Без группы'},'INTL','other']
];
for(const [item,country,topic] of fixtures){
 assert.equal(context.iptvCountry(item),country,JSON.stringify(item));
 assert.equal(context.iptvTopic(item),topic,JSON.stringify(item));
}
assert.deepEqual(Array.from(context.IPTV_COUNTRIES,x=>x.id),['UA','RU','INTL']);
const actualTopicOrder=Array.from(context.IPTV_TOPICS,x=>x.id);
assert.ok(actualTopicOrder.includes('sports')&&actualTopicOrder.includes('news')&&actualTopicOrder.includes('kids'));
assert.ok(preview.includes("if(self.category.indexOf('topic:')===0)"));
assert.ok(preview.includes('iptv-plus-country-badge'));
assert.ok(preview.includes('iptv-plus-subgroup'));
console.log('IPTV+ hierarchy preview: syntax, country/topic fixtures and favorite identity PASS');
