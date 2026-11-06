// Real Chromium checks without npm dependencies. Uses an isolated temporary profile.
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const site=path.resolve(process.env.NW_SITE_DIR||path.join(root,'site','dist')), report=path.join(root,'test_reports');
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
    const mobileShot=await mobile.call('Page.captureScreenshot',{format:'png'});
    await fs.writeFile(path.join(report,'site_locale_mobile.png'),Buffer.from(mobileShot.data,'base64'));
    assert.equal(errors.length,0,JSON.stringify(errors));
    console.log('PASS: English/Chinese auto detection, manual override, persistence, card deep links, English search/details, desktop/mobile overflow and JS errors');
    await send('Browser.close');
}finally{
    if(socket)socket.close();
    chrome.kill();server.close();
    await pause(500);
    assert(profile.startsWith(report+path.sep),'Unsafe cleanup path');
    await fs.rm(profile,{recursive:true,force:true,maxRetries:10,retryDelay:200});
}
