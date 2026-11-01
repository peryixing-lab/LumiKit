const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const zlib = require('node:zlib');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'lumikit-next-'));
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
  async exportBackup() {return JSON.stringify({format:'LumiKit.metadata',version:1,createdAt:Date.now(),documents:[...documents].filter(([key])=>!['workspace','tasks'].includes(key)).map(([key,value])=>({key,value})),history:[]});},
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
const inventory=load('features/inventory/InventoryModels.ets');
const forms=load('features/forms/FormModels.ets');
const drafts=load('features/forms/FormDrafts.ets');
const backup=load('core/PortableBackup.ets');
const files=load('core/FileService.ets').FileService;
const parser=load('features/analytics/XlsxParser.ets');
const xlsx=load('features/analytics/XlsxService.ets');
const presets=load('features/files/FilePresets.ets');
const reminders=load('features/inventory/InventoryReminders.ets');
const plain=value=>JSON.parse(JSON.stringify(value));
let passed=0;
async function test(name,run){await run();passed++;console.log('PASS',name);}
function zip(entries,method=8){
 let offset=0;const locals=[],centrals=[];
 for(const [name,content] of entries){
  const text=Buffer.from(content),filename=Buffer.from(name),encoded=method===8?zlib.deflateRawSync(text):text,crc=backup.lumiCrc(new Uint8Array(text));
  const local=Buffer.alloc(30);local.writeUInt32LE(0x04034b50);local.writeUInt16LE(20,4);local.writeUInt16LE(method,8);local.writeUInt32LE(crc,14);local.writeUInt32LE(encoded.length,18);local.writeUInt32LE(text.length,22);local.writeUInt16LE(filename.length,26);
  locals.push(local,filename,encoded);
  const central=Buffer.alloc(46);central.writeUInt32LE(0x02014b50);central.writeUInt16LE(20,4);central.writeUInt16LE(20,6);central.writeUInt16LE(method,10);central.writeUInt32LE(crc,16);central.writeUInt32LE(encoded.length,20);central.writeUInt32LE(text.length,24);central.writeUInt16LE(filename.length,28);central.writeUInt32LE(offset,42);centrals.push(central,filename);offset+=local.length+filename.length+encoded.length;
 }
 const central=Buffer.concat(centrals),footer=Buffer.alloc(22);footer.writeUInt32LE(0x06054b50);footer.writeUInt16LE(entries.length,8);footer.writeUInt16LE(entries.length,10);footer.writeUInt32LE(central.length,12);footer.writeUInt32LE(offset,16);
 return Buffer.concat([...locals,central,footer]);
}
(async()=>{
 await test('CRC32 detects corruption and composes across streaming chunks',()=>{const text=new TextEncoder().encode('123456789');assert.equal(backup.lumiCrc(text),0xcbf43926);assert.equal(backup.lumiCrc(text.slice(4),backup.lumiCrc(text.slice(0,4))),0xcbf43926);});
 await test('three templates are valid; copies never share form or field IDs',()=>{for(let i=0;i<3;i++){const form=drafts.formTemplate(i);assert.ok(forms.validForm(form));const copy=drafts.copyForm(form);assert.notEqual(copy.id,form.id);assert.ok(copy.fields.every((field,index)=>field.id!==form.fields[index].id));assert.equal(copy.fields.length,form.fields.length);}});
 await test('batch form copies keep unique field IDs even when clock and random values collide',()=>{const clock=Date.now,random=Math.random;try{Date.now=()=>12345;Math.random=()=>0;const source=drafts.formTemplate(0);source.fields=Array.from({length:150},(_,index)=>({...new forms.FormField(),id:'source-'+index,label:'Field '+index}));const copy=drafts.copyForm(source);assert.equal(new Set(copy.fields.map(field=>field.id)).size,150);}finally{Date.now=clock;Math.random=random;}});
 await test('partial schema and answer drafts validate without requiring submission',()=>{const draft=new drafts.LumiFormDraft();draft.schema=drafts.formTemplate(0);draft.mode='fill';draft.answers=[new forms.FieldAnswer()];assert.ok(drafts.validFormDraft(draft));assert.ok(!drafts.validFormDraft({...draft,mode:'invented'}));});
 await test('presets reject unsupported tools, invalid dimensions and unsafe sizes',()=>{const preset={id:'1',name:'邮件',tool:'image-convert',format:1,quality:75,width:'1280',targetMB:''};assert.ok(presets.validFilePreset(preset));for(const change of [{width:'0'},{quality:101},{tool:'json'},{targetMB:'-1'},{format:5}])assert.ok(!presets.validFilePreset({...preset,...change}));});
 await test('reminder plans use local 09:00, exclude returned and archived records',()=>{const item=new inventory.InventoryItem();item.id='item';item.name='相机';item.warrantyReminderDate='2030-01-10';item.warrantyDate='2030-02-10';item.lending=[{id:'active',borrower:'甲',lentAt:'2029-01-01',returnedAt:'',dueDate:'2030-01-11'},{id:'returned',borrower:'乙',lentAt:'2029-01-01',returnedAt:'2029-01-02',dueDate:'2030-01-12'}];const plans=reminders.inventoryReminderPlans([item],new Date(2030,0,1).getTime());assert.equal(plans.length,2);assert.equal(new Date(plans[0].time).getHours(),9);assert.equal(reminders.inventoryReminderPlans([{...item,archived:true}],0).length,0);assert.equal(reminders.inventoryReminderPlans([item],new Date(2031,0,1).getTime()).length,0);});
 await test('multiple reminders get distinct notification IDs and archiving cancels only its own reminder',async()=>{const snapshot=new Map(documents);try{await storage.setSetting('inventoryRemindersEnabled','true');const items=['one','two'].map(id=>({...new inventory.InventoryItem(),id,name:id,warrantyReminderDate:'2030-01-10',warrantyDate:'2030-02-10'}));await reminders.InventoryReminders.sync(items);assert.equal(systemReminders.size,2);assert.equal(new Set([...systemReminders.values()].map(request=>request.notificationId)).size,2);await reminders.InventoryReminders.sync([{...items[0],archived:true},items[1]]);assert.equal(systemReminders.size,1);await reminders.InventoryReminders.sync([]);assert.equal(systemReminders.size,0);}finally{documents.clear();for(const [key,value] of snapshot)documents.set(key,value);}});
 await test('calendar reconciliation deduplicates, updates and removes only LumiKit events',async()=>{const calendar=load('features/inventory/InventoryCalendar.ets').InventoryCalendar;let events=[{id:1,identifier:'user.event',title:'Keep personal event'}];let seq=1;let creates=0;const account={name:'com.lovexjy.LumiKit.reminders',type:'local'};const cal={getAccount:()=>account,async getEvents(){return events.map(v=>({...v}));},async addEvent(event){events.push({...plain(event),id:++seq});return seq;},async updateEvent(event){events=events.map(v=>v.id===event.id?plain(event):v);},async deleteEvent(id){events=events.filter(v=>v.id!==id);},async setConfig(){}};Object.assign(nativeModules['@kit.CalendarKit'].calendarManager,{CalendarType:{LOCAL:'local'},getCalendarManager(){return {async getAllCalendars(){return [cal];},async createCalendar(){creates++;return cal;}};}});const event={type:0,title:'保修',description:'相机',startTime:10000,endTime:20000,identifier:'com.lovexjy.LumiKit.inventory.one',reminderTime:[0]};await calendar.sync({},[event]);assert.equal(events.length,2);events.push({...event,id:++seq});await calendar.sync({},[{...event,title:'Updated',startTime:11000}]);assert.equal(events.length,2);assert.equal(events.find(v=>v.id!==1).title,'Updated');await calendar.sync({},[]);assert.deepEqual(events,[{id:1,identifier:'user.event',title:'Keep personal event'}]);assert.equal(creates,0);});
 await test('empty calendar schedule never creates a new system calendar',async()=>{let creates=0;nativeModules['@kit.CalendarKit'].calendarManager.getCalendarManager=()=>({async getAllCalendars(){return [];},async createCalendar(){creates++;throw Error('unexpected write');}});await load('features/inventory/InventoryCalendar.ets').InventoryCalendar.sync({},[]);assert.equal(creates,0);});
 await test('old inventory records remain valid and malformed reminder dates are rejected',()=>{const item=new inventory.InventoryItem();assert.ok(inventory.validInventoryItem(item));assert.ok(!inventory.validInventoryItem({...item,warrantyReminderDate:'2030-02-30'}));});
 await test('XLSX parses rich strings, sparse rows, inline text, booleans and cached formulas',()=>{const shared=parser.xlsxSharedStrings('<sst><si><t>名称</t></si><si><r><t>中</t></r><r><t>文 &amp; English</t></r></si></sst>');assert.deepEqual(plain(shared),['名称','中文 & English']);const csv=parser.xlsxSheetCsv('<worksheet><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>值</t></is></c><c r="A2"/><c r="B2" t="s"><v>1</v></c><c r="C2"><f>1+1</f><v>2</v></c><c r="C3" t="b"><v>1</v></c></worksheet>',shared);assert.equal(csv,'"名称","","值"\r\n"","中文 & English","2"\r\n"","","true"');});
 await test('XLSX converts Excel dates and rejects invalid shared indices and oversized grids',()=>{const styles=parser.xlsxDateStyles('<styleSheet><cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>');assert.equal(parser.xlsxSheetCsv('<c r="A1" s="1"><v>45292</v></c>',[],styles),'"2024-01-01"');assert.throws(()=>parser.xlsxSheetCsv('<c r="A1" t="s"><v>99</v></c>',[]),/索引/);assert.throws(()=>parser.xlsxSheetCsv('<c r="CW1"><v>x</v></c>',[]),/100/);assert.throws(()=>parser.xlsxSharedStrings('<!DOCTYPE x><si><t>x</t></si>'),/XML/);});
 await test('ZIP preflight rejects path traversal, duplicate paths and truncated packages',()=>{assert.throws(()=>parser.safeZipEntries(new Uint8Array(zip([['../bad','x']]))),/路径/);assert.throws(()=>parser.safeZipEntries(new Uint8Array(zip([['same','x'],['same','y']]))),/路径/);assert.throws(()=>parser.safeZipEntries(new Uint8Array(zip([['good','x']]).subarray(0,30))),/完整|损坏/);assert.equal(parser.safeZipEntries(new Uint8Array(zip([['xl/workbook.xml','x']]))).length,1);});
 const xlsxEntries=[['xl/workbook.xml','<workbook><sheets><sheet name="数据一" r:id="rId1"/><sheet name="空表" r:id="rId2"/></sheets></workbook>'],['xl/_rels/workbook.xml.rels','<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>'],['xl/worksheets/sheet1.xml','<worksheet><c r="A1" t="inlineStr"><is><t>编号</t></is></c><c r="A2" t="inlineStr"><is><t>00123</t></is></c></worksheet>'],['xl/worksheets/sheet2.xml','<worksheet/>']];
 await test('real ZIP/XLSX files load every sheet, preserve leading zeros and verify CRC',async()=>{for(const method of [0,8]){const file=path.join(scratch,'test-'+method+'.xlsx');fs.writeFileSync(file,zip(xlsxEntries,method));const sheets=await xlsx.readXlsx(file);assert.equal(sheets.length,2);assert.equal(sheets[0].name,'数据一');assert.equal(sheets[0].csv,'"编号"\r\n"00123"');assert.equal(sheets[1].csv,'');}const corrupt=zip(xlsxEntries,0);corrupt[30+Buffer.byteLength(xlsxEntries[0][0])+2]^=1;const file=path.join(scratch,'corrupt.xlsx');fs.writeFileSync(file,corrupt);await assert.rejects(xlsx.readXlsx(file),/校验/);});
 const ctx={filesDir:path.join(scratch,'device-one'),cacheDir:path.join(scratch,'cache')};fs.mkdirSync(ctx.filesDir,{recursive:true});fs.mkdirSync(ctx.cacheDir,{recursive:true});
 let archive;
 await test('portable backup streams binary attachments and metadata into a real file',async()=>{const file=await files.writeText(ctx,'发票.txt','中文发票\n00123');const item=new inventory.InventoryItem();item.id='camera';item.name='相机';item.attachments=[{id:'invoice',name:'发票.txt',path:file,size:fs.statSync(file).size}];documents.set('inventory.items',JSON.stringify([item]));archive=await backup.PortableBackup.create(ctx,()=>{});const manifest=await backup.PortableBackup.inspect(ctx,archive.path);assert.equal(manifest.files.length,1);assert.equal(manifest.files[0].crc,backup.lumiCrc(new Uint8Array(fs.readFileSync(file))));});
 await test('cross-device restore remaps attachment paths, indexes files and preserves originals',async()=>{const destination={filesDir:path.join(scratch,'device-two')};fs.mkdirSync(destination.filesDir);const imported=files.outputPath(destination,archive.name);fs.copyFileSync(archive.path,imported);documents.clear();await files.register(destination,imported,archive.name);await backup.PortableBackup.restore(destination,imported,()=>{});const item=JSON.parse(documents.get('inventory.items'))[0];assert.ok(item.attachments[0].path.startsWith(destination.filesDir));assert.equal(fs.readFileSync(item.attachments[0].path,'utf8'),'中文发票\n00123');assert.equal((await files.list(destination)).length,2);});
 await test('corruption and transactional failures leave metadata intact and remove staged files',async()=>{const workspace=files.directory(ctx);const before=fs.readdirSync(workspace).sort();const metadata=documents.get('inventory.items');forceRestoreFailure=true;await assert.rejects(backup.PortableBackup.restore(ctx,archive.path,()=>{}),/transaction/);forceRestoreFailure=false;assert.deepEqual(fs.readdirSync(workspace).sort(),before);assert.equal(documents.get('inventory.items'),metadata);const bytes=fs.readFileSync(archive.path);bytes[bytes.length-1]^=1;const corrupt=files.outputPath(ctx,'坏备份.lumibak');fs.writeFileSync(corrupt,bytes);await assert.rejects(backup.PortableBackup.restore(ctx,corrupt,()=>{}),/校验/);assert.equal(documents.get('inventory.items'),metadata);assert.deepEqual(fs.readdirSync(workspace).sort(),before.concat(path.basename(corrupt)).sort());});
 await test('complete backup refuses to silently omit missing attachments',async()=>{const saved=new Map(documents);documents.clear();const item=new inventory.InventoryItem();item.name='missing';item.attachments=[{id:'missing',name:'missing.pdf',path:ctx.filesDir+'/workspace/missing.pdf',size:10}];documents.set('inventory.items',JSON.stringify([item]));await assert.rejects(backup.PortableBackup.create(ctx,()=>{}),/附件缺失/);documents.clear();for(const [key,value] of saved)documents.set(key,value);});
 await test('portable manifest rejects length tampering before creating files',()=>{const manifest={format:'LumiKit.complete',version:2,metadata:JSON.stringify({format:'LumiKit.metadata',version:1,documents:[],history:[]}),files:[{source:'old',name:'a',size:3,crc:0}]};manifest.metadataCrc=backup.lumiCrc(new TextEncoder().encode(manifest.metadata));assert.throws(()=>backup.validatePortableManifest(manifest,4),/长度/);assert.throws(()=>backup.validatePortableManifest({...manifest,files:[...manifest.files,...manifest.files]},6),/清单/);});
 console.log(`${passed} next-release tests passed. Native SDK doubles are used for PDF, reminders and inflater; device checks remain separate.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>fs.rmSync(scratch,{recursive:true,force:true}));
