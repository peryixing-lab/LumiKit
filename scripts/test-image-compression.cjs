const assert=require('node:assert/strict');
const fs=require('node:fs');const os=require('node:os');const path=require('node:path');const vm=require('node:vm');
const ts=require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'lumi-image-compression-'));const input=path.join(dir,'original.png');const output=path.join(dir,'compressed.jpg');
fs.writeFileSync(input,Buffer.alloc(1000,9));
let scenario={},calls=[],released=0,canceled=false;
const io={OpenMode:{CREATE:fs.constants.O_CREAT,WRITE_ONLY:fs.constants.O_WRONLY,TRUNC:fs.constants.O_TRUNC},statSync:p=>fs.statSync(p),openSync:(p,f)=>({fd:fs.openSync(p,f)}),closeSync:f=>fs.closeSync(f.fd),writeSync:(fd,b)=>fs.writeSync(fd,Buffer.from(b))};
const image={createImageSource:()=>({getImageInfo:async()=>({size:scenario.size||{width:1000,height:500}}),getFrameCount:async()=>scenario.frames||1,createPixelMap:async opts=>({size:opts.desiredSize,release:async()=>{released++;}}),release:async()=>{released++;}}),createImagePacker:()=>({packToData:async(pixel,opts)=>{calls.push({width:pixel.size.width,height:pixel.size.height,quality:opts.quality});if(scenario.fail)throw Error('encoder failed');const size=scenario.bytes?scenario.bytes(pixel,opts):500;return new ArrayBuffer(size);},release:async()=>{released++;}})};
const modules={'@kit.ImageKit':{image},'@kit.CoreFileKit':{fileIo:io},'@kit.ArkTS':{taskpool:{Task:{isCanceled:()=>canceled}}}};
const exportsObject={};vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname,'../entry/src/main/ets/features/files/ImageCompression.ets'),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText,{exports:exportsObject,require:key=>modules[key],Error,Math});
const run=(target=0,width=0,quality=80,format='image/jpeg')=>exportsObject.compressImage(input,output,format,quality,width,target);
async function test(name,fn){scenario={};calls=[];released=0;canceled=false;if(fs.existsSync(output))fs.unlinkSync(output);await fn();assert.equal(fs.readFileSync(input).length,1000);assert.equal(fs.readFileSync(input)[0],9);console.log('PASS',name);}
(async()=>{
 await test('image compression keeps originals and scales down without enlargement',async()=>{await run(0,800);assert.deepEqual(calls,[{width:800,height:400,quality:80}]);assert.equal(fs.statSync(output).size,500);assert.equal(released,3);calls=[];await run(0,2000);assert.equal(calls[0].width,1000);});
 await test('target search stops at the first fitting quality',async()=>{scenario.bytes=(_p,o)=>o.quality*10;assert.equal(await run(500),true);assert.equal(calls.length,3);assert.equal(fs.statSync(output).size,400);});
 await test('unreachable targets keep the smallest smaller result within a bounded search',async()=>{scenario.bytes=(p,o)=>Math.round(p.size.width*o.quality/100);assert.equal(await run(1),true);assert.equal(calls.length,12);assert.equal(fs.statSync(output).size,169);});
 await test('already compact images do not create a larger output',async()=>{scenario.bytes=()=>1200;assert.equal(await run(500),false);assert.ok(!fs.existsSync(output));});
 await test('animated and oversized images fail without flattening or allocating pixels',async()=>{scenario.frames=2;await assert.rejects(run(),/动态图片/);assert.equal(calls.length,0);scenario={size:{width:10000,height:10000}};await assert.rejects(run(),/4,000 万/);assert.equal(calls.length,0);});
 await test('image cancellation and codec errors release resources',async()=>{canceled=true;await assert.rejects(run(),/取消/);assert.equal(released,2);canceled=false;released=0;scenario.fail=true;await assert.rejects(run(),/encoder failed/);assert.equal(released,3);await assert.rejects(run(0,0,80,'image/png'),/JPEG/);});
 console.log('6 image compression policy tests passed; native codecs verified separately on device.');
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>fs.rmSync(dir,{recursive:true,force:true}));
