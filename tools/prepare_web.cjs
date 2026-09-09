const fs=require('fs'),path=require('path'),zlib=require('zlib'),crypto=require('crypto');
const source=process.argv[2],target=process.argv[3];
fs.mkdirSync(target,{recursive:true});
for(const name of fs.readdirSync(source))if(fs.statSync(path.join(source,name)).isFile())fs.copyFileSync(path.join(source,name),path.join(target,name));
const packed={};for(const name of ['index.wasm','index.pck']){
const data=fs.readFileSync(path.join(target,name));const compressed=zlib.gzipSync(data,{level:9});
const output=name+'.'+crypto.createHash('sha256').update(data).digest('hex').slice(0,12)+'.gz';
fs.writeFileSync(path.join(target,output),compressed);packed[name]=output;fs.unlinkSync(path.join(target,name));
if(!zlib.gunzipSync(compressed).equals(data))throw Error('Compression integrity failed');
console.log(`${name}: ${data.length} -> ${compressed.length}`);
}
let html=fs.readFileSync(path.join(target,'index.html'),'utf8');
const bridge=`<script>\nconst packedAssets=${JSON.stringify(packed)};\nconst originalFetch=window.fetch.bind(window);\nwindow.fetch=async function(input,options){const url=new URL(typeof input==='string'?input:input.url||String(input),location.href);const name=url.pathname.split('/').pop();if(url.origin===location.origin&&packedAssets[name]){if(!window.DecompressionStream)throw new Error('请使用最新版 Chrome、Edge 或 Safari 浏览器打开试玩。');url.pathname=url.pathname.replace(name,packedAssets[name]);const response=await originalFetch(url,options);if(!response.ok)throw new Error('游戏加载失败，请刷新重试。');return new Response(response.body.pipeThrough(new DecompressionStream('gzip')),{headers:{'Content-Type':name.endsWith('.wasm')?'application/wasm':'application/octet-stream'}});}return originalFetch(input,options);};\n</script>`;
html=html.replace('<head>','<head>\n'+bridge).replace(/<title>.*?<\/title>/,'<title>墨阵三国 · 战斗试玩</title>').replace('<html','<html lang="zh-CN"');
html=html.replace('</head>','<style>html,body{background:#302e28!important;overscroll-behavior:none}canvas{touch-action:none}#status-notice{font-family:system-ui,sans-serif}</style>\n</head>');
fs.writeFileSync(path.join(target,'index.html'),html);
fs.writeFileSync(path.join(target,'_headers'),'/*\n  Cache-Control: no-cache\n');
for(const name of fs.readdirSync(target)){if(fs.statSync(path.join(target,name)).size>25*1024*1024)throw Error('Asset too large: '+name);}
console.log('Web assets prepared and compression verified.');
