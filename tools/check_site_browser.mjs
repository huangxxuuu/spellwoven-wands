// Real Chromium checks without npm dependencies. Uses an isolated temporary profile.
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const site=path.resolve(process.env.NW_SITE_DIR||path.join(root,'site','dist')), report=path.join(root,'test_reports');
const publicCardCount=JSON.parse(await fs.readFile(path.join(site,'catalog.json'),'utf8')).cards.length;
await fs.mkdir(report,{recursive:true});
const prefix='/spellwoven-wands';
const profile=await fs.mkdtemp(path.join(report,'locale-browser-'));
const server=createServer(async(req,res)=>{
    const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(!pathname.startsWith(prefix+'/')){res.writeHead(404).end();return;}
    const relative=pathname.slice(prefix.length);
    const target=path.resolve(site,'.'+relative+(relative.endsWith('/')?'index.html':''));
    if(!target.startsWith(site+path.sep)){res.writeHead(403).end();return;}
    try{
        const data=await fs.readFile(target);
        const mime={'.html':'text/html','.js':'application/javascript','.json':'application/json','.css':'text/css','.webp':'image/webp','.svg':'image/svg+xml'};
        res.writeHead(200,{'Content-Type':(mime[path.extname(target)]||'application/octet-stream')+'; charset=utf-8'}).end(data);
    }catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=process.env.NW_SITE_URL?.replace(/\/$/,'')||`http://127.0.0.1:${server.address().port}${prefix}`;
const chrome=spawn(process.env.NW_CHROME||'C:/Program Files/Google/Chrome/Application/chrome.exe',[
    '--headless=new','--disable-gpu','--no-first-run','--no-default-browser-check',
    '--remote-debugging-port=0',`--user-data-dir=${profile}`,'about:blank',
],{windowsHide:true,stdio:'ignore'});
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
let socket;
try{
    let port;
    for(let i=0;i<100;i++){
        try{port=(await fs.readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0];break;}catch{await pause(100);}
    }
    assert(port,'Chrome did not start');
    const version=await (await fetch(`http://127.0.0.1:${port}/json/version`)).json();
    socket=new WebSocket(version.webSocketDebuggerUrl);
    await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
    let serial=0;const pending=new Map(), errors=[];
    socket.onmessage=event=>{
        const data=JSON.parse(event.data);
        if(data.id){const task=pending.get(data.id);pending.delete(data.id);data.error?task.reject(data.error):task.resolve(data.result);}
        else if(data.method==='Runtime.exceptionThrown')errors.push(data.params.exceptionDetails);
    };
    function send(method,params={},sessionId){
        return new Promise((resolve,reject)=>{const id=++serial;pending.set(id,{resolve,reject});socket.send(JSON.stringify({id,method,params,sessionId}));});
    }
    async function tab(locale){
        const {browserContextId}=await send('Target.createBrowserContext');
        const {targetId}=await send('Target.createTarget',{url:'about:blank',browserContextId});
        const {sessionId}=await send('Target.attachToTarget',{targetId,flatten:true});
        const call=(method,params)=>send(method,params,sessionId);
        await call('Page.enable');await call('Runtime.enable');
        await call('Page.addScriptToEvaluateOnNewDocument',{source:`Object.defineProperty(navigator,'languages',{get:()=>[${JSON.stringify(locale)}]});`});
        const evaluate=async expression=>{
            const result=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});
            assert(!result.exceptionDetails,JSON.stringify(result.exceptionDetails));return result.result.value;
        };
        const until=async expression=>{
            for(let i=0;i<100;i++){if(await evaluate(expression))return;await pause(100);}
            throw new Error('Timed out: '+expression);
        };
        return {call,evaluate,until};
    }
    const en=await tab('en-US');
    await en.call('Emulation.setDeviceMetricsOverride',{width:1440,height:1000,deviceScaleFactor:1,mobile:false});
    await en.call('Page.navigate',{url:base+'/index.html'});
    await en.until(`document.documentElement.lang==='en' && !!document.querySelector('.language-picker')`);
    assert((await en.evaluate('location.pathname')).endsWith('/en/index.html'));
    assert(await en.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Desktop overflow');
    await pause(300);
    const shot=await en.call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(report,'site_locale_en.png'),Buffer.from(shot.data,'base64'));
    await en.call('Page.navigate',{url:base+'/en/spells.html?card=spark_hit'});
    await en.until(`!!document.querySelector('.spell-card') && document.querySelector('#q').value==='Spark Bolt · Collision'`);
    await en.evaluate(`document.querySelector('.spell-card').click()`);
    assert(await en.evaluate(`document.querySelector('dialog').open && document.querySelector('#detail-content').textContent.includes('Mana cost')`));
    assert(await en.evaluate(`document.querySelector('.spell-data').hidden && document.querySelector('.detail-toggle').getAttribute('aria-expanded')==='false'`));
    assert(await en.evaluate(`document.querySelector('#detail-content > .spell-attrs').getBoundingClientRect().height>0 && !document.querySelector('.spell-data .spell-attrs')`),'Basic stats must remain visible while detailed prose is collapsed');
    assert(await en.evaluate(`!document.querySelector('#detail-content > p.effect').textContent.match(/[0-9]/)`));
    await en.evaluate(`document.querySelector('.detail-toggle').click()`);
    assert(await en.evaluate(`!document.querySelector('.spell-data').hidden && document.querySelector('.detail-toggle').getAttribute('aria-expanded')==='true'`));
    await en.evaluate(`document.querySelector('.detail-toggle').click()`);
    assert(await en.evaluate(`document.querySelector('.spell-data').hidden`));
    for(const [card, fragments] of [
        ['mana_reduce',['Fun -30','Balanced -20','Balanced: Loot Only -20']],
        ['spark',['0.01%','0.05%']],
        ['dark',['Purple Gem ×1','Nightmare Fuel ×2']],
        ['shrink_shot',['Purple Gem ×1','Moon Rock ×3']],
    ]){
        await en.call('Page.navigate',{url:base+'/en/spells.html?card='+card});
        await en.until(`!!document.querySelector('.spell-card') && document.querySelector('#q').value.length>0`);
        await en.evaluate(`document.querySelector('.spell-card').click()`);
        const selector=card==='mana_reduce'?'.difficulty-notes':'#detail-content';
        const displayed=await en.evaluate(`document.querySelector(${JSON.stringify(selector)}).textContent + ' ' + [...document.querySelectorAll('.recipe-material')].map(n=>n.getAttribute('aria-label')).join(' ')`);
        for(const fragment of fragments)assert(displayed.includes(fragment),card+' missing displayed '+fragment);
        assert(await en.evaluate(`document.querySelector('#detail-name').textContent===document.querySelector('#q').value`),card+' deep-link search selected another card');
    }
    await en.call('Page.navigate',{url:base+'/en/spells.html?card=spark_hit'});
    await en.until(`!!document.querySelector('.spell-card') && document.querySelector('#q').value==='Spark Bolt · Collision'`);
    await en.evaluate(`document.querySelector('.spell-card').click()`);
    await en.evaluate(`document.querySelector('#close-detail').click(); const select=document.querySelector('.language-picker select'); select.value='zh';select.dispatchEvent(new Event('change'));`);
    await en.until(`document.documentElement.lang==='zh-CN' && !!document.querySelector('.spell-card')`);
    assert(await en.evaluate(`document.querySelector('.spell-data').hidden && document.querySelector('.detail-toggle').textContent==='详细数据'`));
    assert((await en.evaluate('location.search')).includes('card=spark_hit'),'Card deep link was lost');
    await en.call('Page.reload');
    await en.until(`document.documentElement.lang==='zh-CN' && !!document.querySelector('.spell-card')`);
    const mobile=await tab('zh-CN');
    await mobile.call('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await mobile.call('Page.navigate',{url:base+'/spells.html'});
    await mobile.until(`document.documentElement.lang==='zh-CN' && !!document.querySelector('.spell-card')`);
    await mobile.evaluate(`const select=document.querySelector('.language-picker select');select.value='en';select.dispatchEvent(new Event('change'));`);
    await mobile.until(`document.documentElement.lang==='en' && !!document.querySelector('.spell-card')`);
    assert(await mobile.evaluate('document.documentElement.scrollWidth<=innerWidth'),'Mobile overflow');
    await mobile.evaluate(`document.querySelector('#q').value='homing';document.querySelector('#filters').dispatchEvent(new Event('input'));`);
    assert(await mobile.evaluate(`document.querySelector('#count').textContent.startsWith('Showing ') && document.querySelectorAll('.spell-card').length>0`));
    await mobile.evaluate(`document.querySelector('#q').value='';document.querySelector('#filters').dispatchEvent(new Event('input'));document.querySelector('#tags input[value=music]').click();`);
    assert(await mobile.evaluate(`document.querySelectorAll('.spell-card').length>0`),'Music tag must have results');
    assert(await mobile.evaluate(`(async()=>{const {cards}=await (await fetch('../catalog.en.json')).json();const names=[...document.querySelectorAll('.spell-card')].map(n=>n.textContent);return names.length===cards.filter(c=>c.tagIds.includes('music')).length && names.every(n=>cards.find(c=>c.name===n)?.tagIds.includes('music'));})()`),'Tag results differ from mod data');
    await mobile.evaluate(`document.querySelector('#category').selectedIndex=2;document.querySelector('#filters').dispatchEvent(new Event('input'));`);
    assert(await mobile.evaluate(`(async()=>{const {cards}=await (await fetch('../catalog.en.json')).json();const category=document.querySelector('#category').value;const names=[...document.querySelectorAll('.spell-card')].map(n=>n.textContent);const expected=cards.filter(c=>c.tagIds.includes('music')&&c.category===category);return names.length===expected.length && names.every(n=>expected.some(c=>c.name===n));})()`),'Combined category/tag filter differs from mod data');
    assert(await mobile.evaluate(`!document.querySelector('select#tag') && document.querySelectorAll('#tags input:checked').length===1`),'Tags must be visible single-choice controls');
    await mobile.evaluate(`document.querySelector('#tags input[value=homing]').click()`);
    assert(await mobile.evaluate(`document.querySelectorAll('#tags input:checked').length===1 && document.querySelector('#tags input:checked').value==='homing'`),'Selecting another tag must replace the previous selection');
    await mobile.evaluate(`document.querySelector('#filters button[type=reset]').click()`);
    await mobile.until(`document.querySelector('#tags input:checked').value==='' && document.querySelectorAll('.spell-card').length===${publicCardCount}`);
    assert(await mobile.evaluate(`document.documentElement.scrollWidth<=innerWidth && [...document.querySelectorAll('.tag-option')].every(n=>n.getBoundingClientRect().right<=innerWidth)`),'Tag list must wrap on mobile');
    await mobile.evaluate(`document.querySelector('#category').selectedIndex=1;document.querySelector('#station').selectedIndex=1;document.querySelector('#filters').dispatchEvent(new Event('input'));`);
    assert(await mobile.evaluate(`(async()=>{const {cards}=await (await fetch('../catalog.en.json')).json();const category=document.querySelector('#category').value,station=document.querySelector('#station').value;const available=new Set(cards.filter(c=>c.category===category&&(c.station||'No crafting recipe')===station).flatMap(c=>c.tagIds));return [...document.querySelectorAll('#tags input')].every(n=>!n.value || n.disabled===!available.has(n.value));})()`),'Category and station must jointly determine available tags');
    await mobile.evaluate(`document.querySelector('#filters button[type=reset]').click()`);
    await mobile.until(`document.querySelectorAll('.spell-card').length===${publicCardCount}`);
    await mobile.evaluate(`document.querySelector('#tags input[value=music]').click();document.querySelector('#q').value='spark';document.querySelector('#descriptions').checked=false;document.querySelector('#fuzzy').checked=false;document.querySelector('#filters').dispatchEvent(new Event('input'));`);
    assert(await mobile.evaluate(`document.querySelector('#tags input:checked').value==='' && document.querySelector('#tags input[value=music]').disabled && document.querySelectorAll('.spell-card').length>0`),'An unavailable selected tag must clear after a search');
    assert(await mobile.evaluate(`(async()=>{const {cards}=await (await fetch('../catalog.en.json')).json();const names=[...document.querySelectorAll('.spell-card')].map(n=>n.textContent);const available=new Set(cards.filter(c=>names.includes(c.name)).flatMap(c=>c.tagIds));return [...document.querySelectorAll('#tags input')].every(n=>!n.value || (n.disabled===!available.has(n.value) && (n.parentElement.getBoundingClientRect().width>0)===available.has(n.value)));})()`),'Only tags belonging to matching cards should be displayed');
    await mobile.evaluate(`document.querySelector('#q').value='zzzzzzzzzzzzzz';document.querySelector('#filters').dispatchEvent(new Event('input'));`);
    assert(await mobile.evaluate(`document.querySelectorAll('.spell-card').length===0 && [...document.querySelectorAll('#tags input')].every(n=>!n.value || n.disabled)`),'No results must hide all specific tags');
    await mobile.evaluate(`document.querySelector('#filters button[type=reset]').click()`);
    await mobile.until(`document.querySelectorAll('.spell-card').length===${publicCardCount} && [...document.querySelectorAll('#tags input')].every(n=>!n.disabled)`);
    const mobileShot=await mobile.call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(report,'site_locale_mobile.png'),Buffer.from(mobileShot.data,'base64'));

    // Render every recipe, not just a hand-picked card. Material images must load
    // under the same project prefix as GitHub Pages, in either locale.
    for(const [language, url] of [['en','/en/spells.html?card=dark'],['zh','/spells.html?card=dark']]){
        await en.call('Page.navigate',{url:base+url+'&lang='+language});
        await en.until(`document.documentElement.lang===${JSON.stringify(language==='en'?'en':'zh-CN')} && document.querySelector('#card-detail')?.open && document.querySelector('#detail-content > small:last-child')?.textContent==='dark'`);
        const result=await en.evaluate(`(async()=>{
            const {cards}=await (await fetch(${JSON.stringify(language==='en'?'../catalog.en.json':'catalog.json')})).json();
            const assets=new Set(cards.flatMap(c=>c.recipes.flatMap(r=>r.ingredients.map(i=>i.icon))));
            await Promise.all([...assets].map(async src=>{
                const image=new Image();image.src=${JSON.stringify(language==='en'?'../':'')}+src;await image.decode();
                if(!image.naturalWidth)throw new Error('Empty ingredient image: '+src);
            }));
            let count=0;
            for(const card of cards){
                document.querySelector('dialog').close();showCard(card);
                const rows=[...document.querySelectorAll('.crafting-recipe')];
                if(rows.length!==card.recipes.length)throw new Error(card.id+' missing recipe variants');
                rows.forEach((row,index)=>{
                    const recipe=card.recipes[index], links=[...row.querySelectorAll('.recipe-material')];
                    if(links.length!==recipe.ingredients.length)throw new Error(card.id+' missing ingredient');
                    links.forEach((link,n)=>{
                        const expected=recipe.ingredients[n], img=link.querySelector('img');
                        if(link.dataset.prefab!==expected.prefab || link.querySelector('.ingredient-count').textContent!==String(expected.count)
                            || !link.title.startsWith(expected.name+' ×'+expected.count)
                            || link.getAttribute('href')!==expected.href || !link.getAttribute('aria-label').includes(expected.name+' ×'+expected.count)
                            || !img.src.endsWith('/'+expected.icon) || link.target!=='_blank' || !link.rel.includes('noopener')){
                            throw new Error(card.id+' misrendered '+expected.prefab);
                        }
                    });
                    count++;
                });
                if(!card.recipes.length && document.querySelector('.crafting-recipes').textContent.trim())throw new Error(card.id+' fabricated crafting route');
            }
            document.querySelector('dialog').close();showCard(cards.find(c=>c.id==='dark'));
            await Promise.all([...document.querySelectorAll('.recipe-material img')].map(i=>i.decode()));
            return {recipes:count,images:assets.size};
        })()`);
        assert.equal(result.recipes,154,'All current recipe variants must render');
        assert.equal(result.images,130,'All current ingredient images must load');
        await en.call('Emulation.setDeviceMetricsOverride',{width:1440,height:1200,deviceScaleFactor:1,mobile:false});
        await pause(100);
        const shot=await en.call('Page.captureScreenshot',{format:'png'});
        await fs.writeFile(path.join(report,'site_recipe_'+language+'.png'),Buffer.from(shot.data,'base64'));
        const bounds=await en.evaluate(`(()=>{const r=document.querySelector('.crafting-recipes').getBoundingClientRect();return {x:r.x-8,y:r.y-8,width:r.width+16,height:r.height+16,scale:1};})()`);
        const tiles=await en.call('Page.captureScreenshot',{format:'png',clip:bounds});
        await fs.writeFile(path.join(report,'site_recipe_tiles_'+language+'.png'),Buffer.from(tiles.data,'base64'));
    }
    await en.call('Page.navigate',{url:base+'/spells.html?card=scatter&lang=zh'});
    await en.until(`document.documentElement.lang==='zh-CN' && document.querySelectorAll('.crafting-recipe').length===4`);
    await en.evaluate(`(async()=>{await Promise.all([...document.querySelectorAll('.recipe-material img')].map(i=>i.decode()));document.querySelector('.crafting-recipes').scrollIntoView({block:'start'});})()`);
    const multiBounds=await en.evaluate(`(()=>{const r=document.querySelector('.crafting-recipes').getBoundingClientRect();return {x:r.x-8,y:r.y-8,width:r.width+16,height:r.height+16,scale:1};})()`);
    const multi=await en.call('Page.captureScreenshot',{format:'png',clip:multiBounds});
    await fs.writeFile(path.join(report,'site_recipe_scatter_zh.png'),Buffer.from(multi.data,'base64'));
    await mobile.call('Page.navigate',{url:base+'/en/spells.html?card=scatter'});
    await mobile.until(`document.querySelectorAll('.crafting-recipe').length===4`);
    assert(await mobile.evaluate(`document.documentElement.scrollWidth<=innerWidth && [...document.querySelectorAll('.recipe-material')].every(n=>{
        const r=n.getBoundingClientRect(),d=document.querySelector('dialog').getBoundingClientRect();return r.left>=d.left && r.right<=d.right;
    })`),'Multiple recipe variants overflow the mobile dialog');
    await mobile.call('Page.navigate',{url:base+'/en/spells.html?card=dark'});
    await mobile.until(`document.querySelectorAll('.recipe-material').length===3`);
    await mobile.evaluate(`(async()=>{await Promise.all([...document.querySelectorAll('.recipe-material img')].map(i=>i.decode()));document.querySelector('.crafting-recipes').scrollIntoView({block:'start'});})()`);
    assert(await mobile.evaluate(`document.querySelector('dialog').scrollWidth<=document.querySelector('dialog').clientWidth`),'Recipe dialog horizontal overflow');
    const recipeMobile=await mobile.call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(report,'site_recipe_mobile.png'),Buffer.from(recipeMobile.data,'base64'));
    assert.equal(errors.length,0,JSON.stringify(errors));
    console.log('PASS: English/Chinese auto detection, manual override, persistence, card deep links, English search/details, difficulty values, drop restrictions/rates, all 154 illustrated recipe variants / 130 ingredient images / Wiki or guide links in both languages, mobile recipe wrapping, desktop/mobile overflow and JS errors');
    await send('Browser.close');
}finally{
    if(socket)socket.close();
    chrome.kill();server.close();
    await pause(500);
    assert(profile.startsWith(report+path.sep),'Unsafe cleanup path');
    await fs.rm(profile,{recursive:true,force:true,maxRetries:10,retryDelay:200});
}
