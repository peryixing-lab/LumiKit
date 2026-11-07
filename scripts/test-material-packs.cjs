const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'lumikit-materials-'));
const documents = new Map();
let failNextWrite = false;
const storage = {
  async getValue(key, fallback = '') { return documents.get(key) ?? fallback; },
  async setValue(key, value) { if (failNextWrite) { failNextWrite = false; throw Error('injected write failure'); } documents.set(key, value); },
  async exportBackup() { return JSON.stringify({format:'LumiKit.metadata',version:1,createdAt:Date.now(),documents:[...documents].filter(([key])=>!['workspace','tasks','file.sessions','workbench.sessions'].includes(key)).map(([key,value])=>({key,value})),history:[]}); },
  async restoreBackup(text, local = []) { const backup = JSON.parse(text); for (const entry of [...backup.documents,...local]) documents.set(entry.key,entry.value); }
};
const io = {
  OpenMode:{READ_ONLY:fs.constants.O_RDONLY,WRITE_ONLY:fs.constants.O_WRONLY,CREATE:fs.constants.O_CREAT,TRUNC:fs.constants.O_TRUNC},
  accessSync:file=>fs.existsSync(file), mkdirSync:(file,recursive)=>fs.mkdirSync(file,{recursive}),
  statSync:file=>fs.statSync(file), lstatSync:file=>fs.lstatSync(file),
  async open(file,flags){return {fd:fs.openSync(file,flags)};}, async close(file){fs.closeSync(file.fd);},
  async read(fd,data){return fs.readSync(fd,Buffer.from(data),0,data.byteLength,null);},
  async write(fd,data){const bytes=typeof data==='string'?Buffer.from(data):Buffer.from(data);return fs.writeSync(fd,bytes,0,bytes.length,null);},
  async unlink(file){fs.unlinkSync(file);}, async stat(file){return fs.statSync(file);}, async copyFile(source,target){fs.copyFileSync(source,target);}
};
const native = {
  '@kit.AbilityKit':{},'@kit.ShareKit':{},'@kit.ArkData':{},'@kit.CoreFileKit':{fileIo:io},
  '@kit.ArkTS':{util:{TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text);}},TextDecoder:class{decodeToString(bytes){return new TextDecoder('utf-8',{fatal:true}).decode(bytes);}}}}
};
const cache = new Map([[path.join(root,'core/StorageService.ets'),{StorageService:storage}]]);
function load(relative){
  const file=path.isAbsolute(relative)?relative:path.join(root,relative);
  if(cache.has(file))return cache.get(file);
  const exports={};cache.set(file,exports);
  const source=fs.readFileSync(file,'utf8').replace(/^@Concurrent\s*$/mg,'');
  const result=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021},reportDiagnostics:true});
  assert.equal(result.diagnostics.length,0);
  vm.runInNewContext(result.outputText,{exports,require:name=>native[name]||load(path.resolve(path.dirname(file),name)+'.ets'),Date,Math,Array,Map,Set,Uint8Array,Uint32Array,DataView,ArrayBuffer,JSON,Number,String,Promise,Error});
  return exports;
}
const models=load('features/materials/MaterialPackModels.ets');
const store=load('features/materials/MaterialPackStore.ets').LumiMaterialPackStore;
const files=load('core/FileService.ets').FileService;
const portable=load('core/PortableBackup.ets');
const validate=load('core/BackupValidation.ets').validateBackupDocument;
const plain=value=>JSON.parse(JSON.stringify(value));
const item=(id,name='申请表',extra={})=>({...new models.LumiMaterialItem(),id,name,...extra});
const pack=(id,items=[])=>({...new models.LumiMaterialPack(),id,name:'报名材料',items,createdAt:1,updatedAt:1});
let passed=0;
async function test(name,run){await run();passed++;console.log('PASS',name);}
const ctx={filesDir:path.join(scratch,'source')};fs.mkdirSync(ctx.filesDir);
async function make(name,content){const file=files.outputPath(ctx,name);fs.writeFileSync(file,content);return files.register(ctx,file,name);}
(async()=>{
  await test('requirements reject invalid sizes, formats, duplicate item ids and excess items',()=>{
    const valid=pack('one',[item('a')]);assert.ok(models.validMaterialPack(valid));
    for(const change of [{name:''},{format:'docx'},{maxMB:'NaN'},{maxMB:'0'},{maxMB:'-1'},{maxMB:'100.1'},{maxMB:5},{path:null}])assert.ok(!models.validMaterialPack(pack('one',[item('a','申请表',change)])));
    assert.ok(!models.validMaterialPack(pack('one',[item('a'),item('a')])));
    assert.ok(!models.validMaterialPack(pack('one',Array.from({length:21},(_,i)=>item('a'+i)))));
    assert.ok(!models.validMaterialPack({...valid,updatedAt:Infinity}));
  });
  await test('status checks actual filename and byte size at the exact decimal MB boundary',()=>{
    const requirement=item('photo','证件照片',{format:'jpeg',maxMB:'0.5',path:'/bound/photo'});
    assert.equal(models.materialItemStatus(requirement,'portrait.JPG',524288),'已准备');
    assert.equal(models.materialItemStatus(requirement,'portrait.jpg',524289),'超出大小');
    assert.equal(models.materialItemStatus(requirement,'portrait.png',10),'格式不符合');
    assert.equal(models.materialItemStatus(requirement,'',-1),'待添加');
    assert.equal(models.materialItemStatus({...requirement,path:''},'portrait.jpg',10),'待添加');
    assert.ok(models.materialFormatMatches('text','笔记.MarkDown'));
    assert.ok(!models.materialFormatMatches('pdf','申请.pdf.exe'));
  });
  await test('template contains requirements without any binding or shared mutable items',()=>{
    const source=pack('one',[item('a','照片',{path:'/private/photo.png',format:'image',maxMB:'1'})]);
    const template=models.materialTemplateFromPack(source,'template','照片清单');
    assert.ok(models.validMaterialTemplate(template));assert.equal(template.items[0].path,'');
    template.items[0].name='改名';assert.equal(source.items[0].name,'照片');
    assert.ok(!models.validMaterialTemplate({...template,items:source.items}));
  });
  await test('concurrent pack saves preserve independent records and snapshot the caller',async()=>{
    const first=pack('first',[item('a')]);const pending=store.putPack(first);first.items[0].name='mutated';
    await Promise.all([pending,store.putPack(pack('second',[item('b')]))]);
    const saved=await store.packs();assert.equal(saved.length,2);assert.equal(saved.find(p=>p.id==='first').items[0].name,'申请表');
    await store.putPack({...saved[0],name:'已修改'});assert.equal((await store.packs()).length,2);
  });
  await test('a failed save keeps existing data and does not poison the write queue',async()=>{
    const before=documents.get('material.packs');failNextWrite=true;
    await assert.rejects(store.putPack(pack('failed')),/injected/);assert.equal(documents.get('material.packs'),before);
    await store.putPack(pack('after-failure'));assert.ok((await store.packs()).some(p=>p.id==='after-failure'));
  });
  await test('record bounds do not silently drop the oldest pack or template',async()=>{
    documents.set('material.packs',JSON.stringify(Array.from({length:30},(_,i)=>pack('p'+i))));
    await assert.rejects(store.putPack(pack('extra')),/30/);assert.equal((await store.packs()).length,30);
    const template=models.materialTemplateFromPack(pack('p',[item('a')]),'template','清单');
    await store.putTemplate(template);assert.equal((await store.templates())[0].items[0].path,'');
    documents.set('material.templates',JSON.stringify([template,template]));await assert.rejects(store.templates(),/模板/);
    documents.clear();
  });
  const original=await make('申请表.pdf','unchanged application bytes');
  const sourcePack=pack('application',[item('form','申请表',{path:original.path,format:'pdf',maxMB:'1'})]);
  await store.putPack(sourcePack);
  await store.putTemplate(models.materialTemplateFromPack(sourcePack,'application-template','报名清单'));
  await test('backup validation accepts material modules and rejects malformed or duplicate records',()=>{
    assert.ok(validate('material.packs',JSON.stringify([sourcePack])));
    assert.ok(!validate('material.packs',JSON.stringify([sourcePack,sourcePack])));
    assert.ok(!validate('material.packs',JSON.stringify([{...sourcePack,items:[item('bad','',{maxMB:'Infinity'})]}])));
    assert.ok(!validate('material.templates',JSON.stringify([{...models.materialTemplateFromPack(sourcePack,'t','清单'),items:sourcePack.items}])));
  });
  await test('complete backup permits generated files over 100 MB but enforces the 1 GB total',()=>{
    const metadata=JSON.stringify({format:'LumiKit.metadata',version:1,createdAt:1,documents:[],history:[]});
    const manifest={format:'LumiKit.complete',version:2,createdAt:1,metadata,metadataCrc:portable.lumiCrc(new TextEncoder().encode(metadata)),files:[{source:'/generated/batch.zip',name:'批量文件.zip',size:150*1024*1024,crc:0}]};
    assert.doesNotThrow(()=>portable.validatePortableManifest(manifest,150*1024*1024));
    const oversized=plain(manifest);oversized.files[0].size=1024*1024*1024;
    oversized.files.push({source:'/generated/extra.txt',name:'extra.txt',size:1,crc:0});
    assert.throws(()=>portable.validatePortableManifest(oversized,1024*1024*1024+1),/1 GB/);
    const unsafe=plain(manifest);unsafe.files[0].size=Number.MAX_SAFE_INTEGER+1;
    assert.throws(()=>portable.validatePortableManifest(unsafe,unsafe.files[0].size),/清单/);
  });
  let archive;
  await test('complete backup includes material file bytes and rejects unpacked bound paths',async()=>{
    archive=await portable.PortableBackup.create(ctx,()=>{});
    const manifest=await portable.PortableBackup.inspect(ctx,archive.path);
    const tampered=plain(manifest);const data=JSON.parse(tampered.metadata);
    const entry=data.documents.find(document=>document.key==='material.packs');const saved=JSON.parse(entry.value);saved[0].items[0].path='/missing/elsewhere.pdf';entry.value=JSON.stringify(saved);
    tampered.metadata=JSON.stringify(data);tampered.metadataCrc=portable.lumiCrc(new TextEncoder().encode(tampered.metadata));
    assert.throws(()=>portable.validatePortableManifest(tampered,tampered.files.reduce((sum,file)=>sum+file.size,0)),/未打包/);
  });
  await test('restore onto another device remaps material references and preserves template isolation',async()=>{
    const destination={filesDir:path.join(scratch,'destination')};fs.mkdirSync(destination.filesDir);
    const imported=files.outputPath(destination,archive.name);fs.copyFileSync(archive.path,imported);documents.clear();await files.register(destination,imported,archive.name);
    await portable.PortableBackup.restore(destination,imported,()=>{});
    const restored=(await store.packs())[0];assert.notEqual(restored.items[0].path,original.path);
    assert.ok(restored.items[0].path.startsWith(destination.filesDir));assert.equal(fs.readFileSync(restored.items[0].path,'utf8'),'unchanged application bytes');
    assert.equal((await store.templates())[0].items[0].path,'');
    await store.deletePack(restored.id);assert.ok(fs.existsSync(restored.items[0].path));
  });
  await test('missing material file prevents creating an apparently complete backup',async()=>{
    await store.putPack(pack('missing',[item('missing','缺失材料',{path:'/missing/document.pdf'})]));
    await assert.rejects(portable.PortableBackup.create({filesDir:path.join(scratch,'destination')},()=>{}),/材料包.*缺失/);
  });
  console.log(`${passed} material pack tests passed. Device UI and native delivery require separate validation.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>fs.rmSync(scratch,{recursive:true,force:true}));
