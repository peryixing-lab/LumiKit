const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const zlib = require('node:zlib');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'lumikit-workbench-'));
const io = {
  OpenMode: {READ_ONLY: fs.constants.O_RDONLY, WRITE_ONLY: fs.constants.O_WRONLY, CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC},
  accessSync: file => fs.existsSync(file), mkdirSync: (file, recursive) => fs.mkdirSync(file,{recursive}),
  statSync: file => fs.statSync(file), lstatSync: file => fs.lstatSync(file), listFileSync: file => fs.readdirSync(file),
  async open(file, flags) {return {fd:fs.openSync(file,flags)};}, async close(file) {fs.closeSync(file.fd);},
  async read(fd, data) {return fs.readSync(fd,Buffer.from(data),0,Math.min(data.byteLength,65536),null);},
  async write(fd,data) {const buffer=typeof data==='string'?Buffer.from(data):Buffer.from(data); return fs.writeSync(fd,buffer,0,buffer.length,null);},
  async unlink(file) {fs.unlinkSync(file);}, async stat(file) {return fs.statSync(file);}, async readText(file) {return fs.readFileSync(file,'utf8');},
  async copyFile(source,target) {fs.copyFileSync(source,target);}
};
const documents = new Map(); let forceRestoreFailure=false;
const storage = {
  async getValue(key,fallback='') {return documents.get(key)??fallback;},
  async setValue(key,value) {documents.set(key,value);},
  async exportBackup() {return JSON.stringify({format:'LumiKit.metadata',version:1,createdAt:Date.now(),documents:[...documents].filter(([key])=>!['workspace','tasks','file.sessions','workbench.sessions'].includes(key)).map(([key,value])=>({key,value})),history:[]});},
  async restoreBackup(text, local=[]) {if(forceRestoreFailure)throw Error('transaction failure');const backup=JSON.parse(text); for(const entry of [...backup.documents,...local])documents.set(entry.key,entry.value);},
  async getSetting(key,fallback='') {return documents.get('setting:'+key)??fallback;}, async setSetting(key,value){documents.set('setting:'+key,value);}
};
const systemReminders=new Map();let reminderSequence=0;
const nativeModules = {
 '@kit.CalendarKit': {calendarManager:{}}, '@kit.AbilityKit': {}, '@kit.ShareKit': {}, '@kit.ArkData': {},
 '@kit.CoreFileKit': {fileIo:io}, '@kit.ImageKit': {}, '@kit.PDFKit': {}, '@kit.NotificationKit': {}, '@kit.BackgroundTasksKit': {reminderAgentManager:{ReminderType:{REMINDER_TYPE_CALENDAR:1},async publishReminder(request){for(const [id,entry] of systemReminders)if(entry.notificationId===request.notificationId)systemReminders.delete(id);const id=++reminderSequence;systemReminders.set(id,request);return id;},async cancelReminder(id){if(!systemReminders.delete(id))throw {code:1700003};}}},
 '@kit.ArkTS': {util:{TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text);}},TextDecoder:class{decodeToString(bytes){return new TextDecoder('utf-8',{fatal:true}).decode(bytes);}}}},
 '@kit.BasicServicesKit':{zlib:{CompressFlushMode:{FINISH:4},ReturnStatus:{STREAM_END:1},async createZip(){return {
   async inflateInit2(){return 0;},async inflate(stream){const result=zlib.inflateRawSync(Buffer.from(stream.nextIn),{maxOutputLength:stream.availableOut});new Uint8Array(stream.nextOut).set(result);stream.totalOut=result.length;stream.totalIn=stream.nextIn.byteLength;this.stream=stream;return 1;},async getZStream(){return {totalIn:this.stream.totalIn,totalOut:this.stream.totalOut};},async inflateEnd(){}
 };}}}
};
const cache=new Map([[path.join(root,'core/StorageService.ets'),{StorageService:storage}]]);
function load(relative){
 const file=path.isAbsolute(relative)?relative:path.join(root,relative);
 if(cache.has(file))return cache.get(file);
 const exports={};cache.set(file,exports);
 const source=fs.readFileSync(file,'utf8').replace(/^@Concurrent\s*$/mg,'');
 const transpiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021},reportDiagnostics:true});
 assert.equal(transpiled.diagnostics.length,0,transpiled.diagnostics.map(d=>d.messageText).join('\n'));
 vm.runInNewContext(transpiled.outputText,{exports,require:name=>nativeModules[name]||load(path.resolve(path.dirname(file),name)+'.ets'),Date,Math,Array,Map,Set,Uint8Array,DataView,ArrayBuffer,JSON,Number,String,Promise,Error});
 return exports;
}
const files=load('core/FileService.ets').FileService;
const backup=load('core/PortableBackup.ets');
const models=load('features/workbench/WorkbenchModels.ets');
const store=load('features/workbench/WorkbenchStore.ets').WorkbenchStore;
const receipt=load('features/inventory/ReceiptCandidates.ets').receiptCandidates;
const validate=load('core/BackupValidation.ets').validateBackupDocument;
const plain=value=>JSON.parse(JSON.stringify(value));
let passed=0;
async function test(name,run){await run();passed++;console.log('PASS',name);}
const ctx={filesDir:path.join(scratch,'one')}; fs.mkdirSync(ctx.filesDir);
async function make(name,body='fixture'){const p=files.outputPath(ctx,name);fs.writeFileSync(p,body);return files.register(ctx,p,name);}
(async()=>{
 await test('receipt uses explicit labels and leaves unlabeled text empty',()=>{
   assert.deepEqual(plain(receipt('商品名称：随身相机\n购买日期：2026年10月12日\n实付款：￥1,299.00')), {name:'随身相机',purchaseDate:'2026-10-12',price:'1299.00'});
   assert.deepEqual(plain(receipt('随身相机 1299\n2026-10-12\n保修一年')), {name:'',purchaseDate:'',price:''});
 });
 await test('receipt rejects ambiguous dates, ambiguous totals and invalid dates',()=>{
   const result=receipt('购买日期：2026-10-12\n开票日期：2026-10-13\n实付款：20\n合计金额：25');assert.equal(result.purchaseDate,'');assert.equal(result.price,'');
   assert.equal(receipt('交易日期：2026-02-30').purchaseDate,'');assert.equal(receipt('实付：20.00\n实付金额：20.00').price,'20.00');
   assert.equal(receipt('商品名称：\n手写笔').name,'手写笔');
 });
 await test('recipe validation and backup validation bound parameters and reject unsupported kinds',()=>{
   const recipe={...new models.LumiFlowRecipe(),id:'recipe',name:'每周材料'};
   assert.ok(models.validFlowRecipe(recipe));assert.ok(validate('workbench.recipes',JSON.stringify([recipe])));
   for(const diff of [{quality:101},{targetMB:'Infinity'},{targetMB:'0'},{kind:'arbitrary'},{outputName:''}])assert.ok(!models.validFlowRecipe({...recipe,...diff}));
   assert.ok(!validate('workbench.recipes',JSON.stringify([recipe,recipe])));
 });
 await test('page states reject duplicates, invalid rotation and out-of-bounds page numbers',()=>{
   assert.ok(models.validSavedPages([{original:0,rotation:90}]));
   for(const pages of [[{original:0,rotation:1}],[{original:200,rotation:0}],[{original:0,rotation:0},{original:0,rotation:90}]])assert.ok(!models.validSavedPages(pages));
 });
 const source=await make('购买凭证.txt','原始凭证');let final=await make('材料.pdf','PDF fixture for byte-preserving backup');
 await test('rename preserves paths, attachment references and extension while normalizing tags',async()=>{
   const original=final.path;final.name='提交/材料';final.tags=['报销',' 报销 ','待提交'];final.role='final';final.sourcePaths=[source.path];final.collectionId='collection';
   await files.updateDetails(ctx,final);final=(await files.list(ctx)).find(file=>file.path===original);
   assert.equal(final.path,original);assert.equal(final.name,'提交_材料.pdf');assert.deepEqual(plain(final.tags),['报销','待提交']);assert.equal(fs.readFileSync(source.path,'utf8'),'原始凭证');
 });
 await test('trash persists and restores grouping, tags and provenance without changing bytes',async()=>{
   await files.remove(ctx,final);assert.ok(!(await files.list(ctx)).some(f=>f.path===final.path));
   const trashed=(await files.list(ctx,true)).find(f=>f.path===final.path);assert.ok(trashed.trashedAt);assert.equal(trashed.collectionId,'collection');assert.deepEqual(plain(trashed.sourcePaths),[source.path]);
   await files.setTrash(ctx,final,false);assert.equal((await files.list(ctx)).find(f=>f.path===final.path).collectionId,'collection');
 });
 await test('attachments, form drafts, file drafts and active workflows block trash',async()=>{
   for(const [key,data] of [['inventory.items',[{attachments:[{path:final.path}]}]],['forms.responses',[{answers:[{attachments:[{path:final.path}]}]}]],['forms.autodraft',{answers:[{attachments:[{path:final.path}]}]}],['file.sessions',[{paths:[final.path]}]],['workbench.sessions',[{inputs:[final.path],finalPath:''}]]]){
     documents.set(key,JSON.stringify(data));await assert.rejects(files.remove(ctx,final));assert.ok(fs.existsSync(final.path));documents.delete(key);
   }
 });
 await test('concurrent rename and trash retain both changes; registering another file never loses trash',async()=>{
   await Promise.all([files.updateDetails(ctx,{...final,name:'已核对.pdf'}),files.remove(ctx,final)]);
   await make('其他.txt');const current=(await files.list(ctx,true)).find(f=>f.path===final.path);assert.ok(current.trashedAt);assert.equal(current.name,'已核对.pdf');
 });
 await test('permanent deletion only accepts trash and rechecks attachment references',async()=>{
   await assert.rejects(files.deletePermanently(ctx,source));documents.set('inventory.items',JSON.stringify([{attachments:[{path:final.path}]}]));await assert.rejects(files.deletePermanently(ctx,final));documents.delete('inventory.items');
   const temp=await make('临时.txt');await files.remove(ctx,temp);await files.deletePermanently(ctx,temp);assert.ok(!fs.existsSync(temp.path));assert.ok(!(await files.list(ctx,true)).some(f=>f.path===temp.path));
 });
 await test('concurrent session saves preserve independent drafts and snapshot mutable caller data',async()=>{
   const a={...new models.LumiFileSession(),toolId:'images-pdf',paths:[source.path],updatedAt:10};const b={...new models.LumiFileSession(),toolId:'pdf-edit',paths:[final.path],updatedAt:20,edits:[{original:0,rotation:90}]};
   const pending=store.putFileSession(a);a.name='changed after save started';await Promise.all([pending,store.putFileSession(b)]);const saved=await store.fileSessions();assert.equal(saved.length,2);assert.equal(saved.find(s=>s.toolId==='images-pdf').name,'');assert.equal(saved[0].toolId,'pdf-edit');
   await store.putFileSession({...new models.LumiFileSession(),toolId:'pdf-edit'});assert.equal((await store.fileSessions()).length,1);documents.delete('file.sessions');
 });
 await test('workflow stores a resumable checkpoint and preserves earlier steps on failure',async()=>{
   const session={...new models.LumiFlowSession(),id:'flow',inputs:[source.path],prepared:[source.path],basePath:source.path,stage:1,edits:[{original:0,rotation:90}],updatedAt:1};
   await store.putFlow(session);await store.putFlow({...session,error:'injected native failure'});const restored=(await store.flows())[0];assert.deepEqual(plain(restored.prepared),[source.path]);assert.equal(restored.stage,1);assert.equal(restored.edits[0].rotation,90);await store.deleteFlow('flow');assert.equal((await store.flows()).length,0);
 });
 await test('complete backup carries collections, recipes, trash and remaps source relationships across devices',async()=>{
   await store.putCollection({id:'collection',name:'每周材料',createdAt:1});await store.putRecipe({...new models.LumiFlowRecipe(),id:'recipe',name:'每周提交'});
   const archive=await backup.PortableBackup.create(ctx,()=>{});const manifest=await backup.PortableBackup.inspect(ctx,archive.path);
   const data=JSON.parse(manifest.metadata);assert.ok(!data.documents.some(d=>d.key==='workbench.sessions'||d.key==='file.sessions'));
   const destination={filesDir:path.join(scratch,'two')};fs.mkdirSync(destination.filesDir);const imported=files.outputPath(destination,archive.name);fs.copyFileSync(archive.path,imported);documents.clear();await files.register(destination,imported,archive.name);
   await store.putCollection({id:'existing-collection',name:'本机原有集合',createdAt:2});
   const localPath=files.outputPath(destination,'本机文件.txt');fs.writeFileSync(localPath,'keep');const local=await files.register(destination,localPath,'本机文件.txt');local.collectionId='existing-collection';await files.updateDetails(destination,local);
   await backup.PortableBackup.restore(destination,imported,()=>{});
   assert.ok((await store.collections()).some(group=>group.id==='existing-collection' && group.name==='本机原有集合'));
   assert.equal((await files.list(destination)).find(file=>file.path===localPath).collectionId,'existing-collection');
   const all=await files.list(destination,true);const restored=all.find(f=>f.name==='已核对.pdf');assert.ok(restored.trashedAt);assert.equal(restored.role,'final');assert.equal(restored.collectionId,'collection');assert.ok(restored.sourcePaths[0].startsWith(destination.filesDir));assert.equal(fs.readFileSync(restored.sourcePaths[0],'utf8'),'原始凭证');
   await files.setTrash(destination,restored,false);assert.ok((await files.list(destination)).some(f=>f.path===restored.path));assert.equal((await store.collections())[0].name,'每周材料');assert.equal((await store.recipes())[0].name,'每周提交');
   const tampered=plain(manifest);tampered.files[0].details.tags=[42];assert.throws(()=>backup.validatePortableManifest(tampered,tampered.files.reduce((n,f)=>n+f.size,0)),/关联信息/);
 });
 console.log(`${passed} workbench tests passed. Native processing and UI require device validation.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>fs.rmSync(scratch,{recursive:true,force:true}));
