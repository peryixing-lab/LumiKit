const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const sdk = process.env.HARMONY_SDK_HOME || '/Applications/DevEco-Studio.app/Contents/sdk/default';
const ts = require(path.join(sdk, 'openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
class Rows {
  constructor(rows) { this.rows = rows; this.index = -1; this.closed = false; }
  goToFirstRow() { this.index = 0; return this.rows.length > 0; }
  goToNextRow() { return ++this.index < this.rows.length; }
  getString(index) { return String(this.rows[this.index][index]); }
  getDouble(index) { return Number(this.rows[this.index][index]); }
  close() { this.closed = true; }
}
const db = {
  version: 0, documents: new Map(), history: new Map(), failKey: '', rollbacks: 0,
  async beginTransaction() { this.snapshot = [new Map(this.documents), new Map(this.history)]; },
  async commit() { this.snapshot = undefined; },
  async rollBack() { this.rollbacks++; [this.documents, this.history] = this.snapshot; this.snapshot = undefined; },
  async executeSql(sql) { if (sql === 'DELETE FROM history') this.history.clear(); },
  async insert(table, record) {
    if (record.key === this.failKey) throw Error('injected write failure');
    (table === 'documents' ? this.documents : this.history).set(record.key || record.id, {...record});
  },
  async querySql(sql, args = []) {
    if (sql.includes('SELECT value')) return new Rows(this.documents.has(args[0]) ? [[this.documents.get(args[0]).value]] : []);
    if (sql.includes('SELECT key')) return new Rows([...this.documents.values()].filter(row => !['workspace','tasks'].includes(row.key)).map(row => [row.key, row.value]));
    return new Rows([...this.history.values()].map(row => [row.id, row.tool_id, row.title, row.detail, row.created_at, row.output_path]));
  }
};
const settings = new Map();
let sequence = 0;
const modules = {
  '@kit.ArkData': {
    preferences: {getPreferences: async () => ({get: async (key, fallback) => settings.get(key) ?? fallback, put: async (key, value) => settings.set(key,value), flush: async () => {}})},
    relationalStore: {getRdbStore: async () => db, SecurityLevel: {S2: 2}, ConflictResolution: {ON_CONFLICT_REPLACE: 1}}
  },
  '@kit.ArkTS': {util: {generateRandomUUID: () => 'uuid-' + ++sequence, TextEncoder: class {encodeInto(value) {return new TextEncoder().encode(value);}}}}
};
const cache = new Map();
function load(file) {
  if (cache.has(file)) return cache.get(file);
  const exports = {}; cache.set(file,exports);
  const requireLocal = name => {
    if (modules[name]) return modules[name];
    const target = path.resolve(path.dirname(file),name);
    return load(fs.existsSync(target+'.ets') ? target+'.ets' : target+'.ts');
  };
  const code = ts.transpileModule(fs.readFileSync(file,'utf8'), {compilerOptions: {module: ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2021}}).outputText;
  vm.runInNewContext(code, {exports,require:requireLocal});
  return exports;
}
const store = load(path.join(__dirname, '../entry/src/main/ets/core/StorageService.ets')).StorageService;
const backup = (docs, history = []) => JSON.stringify({format:'LumiKit.metadata',version:1,documents:docs,history});
let passed = 0;
async function test(name, run) { await run(); passed++; console.log('PASS', name); }
(async () => {
  await test('initializes RDB once and advances schema', async () => { await Promise.all([store.init({}),store.init({})]); assert.equal(db.version,1); });
  await test('documents round trip and fallback is explicit', async () => { await store.setValue('favorites','["json"]'); assert.equal(await store.getValue('favorites'),'["json"]'); assert.equal(await store.getValue('missing','fallback'),'fallback'); });
  await test('history settings suppress future records without deleting prior records', async () => { await store.addHistory('json','格式化','使用记录'); await store.setSetting('historyEnabled','false'); await store.addHistory('hash','哈希','使用记录'); assert.equal((await store.getHistory()).length,1); });
  await test('metadata backup omits physical workspace index', async () => { await store.setValue('workspace','[{"path":"existing-file"}]'); const data = JSON.parse(await store.exportBackup()); assert.equal(data.documents.some(doc => doc.key === 'workspace'),false); });
  await test('invalid and oversized backup rejected before write', async () => { await assert.rejects(store.restoreBackup('null')); await assert.rejects(store.restoreBackup(backup([{key:'favorites',value:'{}'}]))); await assert.rejects(store.restoreBackup('x'.repeat(4*1024*1024+1))); assert.equal(await store.getValue('favorites'),'["json"]'); });
  await test('malformed domain arrays cannot replace valid records', async () => { await assert.rejects(store.restoreBackup(backup([{key:'inventory.items',value:'[{}]'}]))); await assert.rejects(store.restoreBackup(backup([{key:'forms.schemas',value:'[{}]'}]))); await assert.rejects(store.restoreBackup(backup([{key:'favorites',value:'[\"invented\"]'}]))); });
  await test('UTF-8 bytes limit matches file import rather than UTF-16 length', async () => { await assert.rejects(store.restoreBackup(backup([{key:'inventory.items',value:JSON.stringify(['中'.repeat(1500000)])}]))); });
  await test('restore preserves current file index and restores metadata', async () => { await store.restoreBackup(backup([{key:'favorites',value:'["hash"]'},{key:'workspace',value:'[]'}])); assert.equal(await store.getValue('favorites'),'["hash"]'); assert.equal(await store.getValue('workspace'),'[{"path":"existing-file"}]'); });
  await test('restore merges history by ID and preserves newer local records', async () => {
    const original = (await store.getHistory())[0];
    await store.setSetting('historyEnabled','true');
    await store.addHistory('uuid','恢复前新增','本地记录');
    await store.setSetting('historyEnabled','false');
    const local = (await store.getHistory()).find(record => record.id !== original.id);
    const imported = {id:'imported-history',toolId:'hash',title:'备份独有记录',detail:'导入记录',createdAt:1,outputPath:''};
    await store.restoreBackup(backup([], [{...original,title:'同 ID 的备份记录'}, imported]));
    const restored = await store.getHistory();
    assert.equal(restored.length,3);
    assert.equal(restored.find(record => record.id === original.id).title,'同 ID 的备份记录');
    assert.equal(restored.find(record => record.id === local.id).title,'恢复前新增');
    assert.equal(restored.find(record => record.id === imported.id).title,'备份独有记录');
  });
  await test('failed restore rolls back all prior changes', async () => { db.failKey='inventory.items'; await assert.rejects(store.restoreBackup(backup([{key:'favorites',value:'[]'},{key:'inventory.items',value:'[]'}]))); db.failKey=''; assert.equal(await store.getValue('favorites'),'["hash"]'); assert.equal(db.rollbacks,1); });
  await test('portable restore commits metadata and local file index in one transaction', async () => {
    const current = await store.getValue('workspace');
    db.failKey='workspace';
    await assert.rejects(store.restoreBackup(backup([{key:'favorites',value:'[]'}]),[{key:'workspace',value:'[{"path":"staged"}]'}]));
    db.failKey=''; assert.equal(await store.getValue('favorites'),'["hash"]'); assert.equal(await store.getValue('workspace'),current);
    await store.restoreBackup(backup([{key:'favorites',value:'["hash"]'}]),[{key:'workspace',value:'[{"path":"restored"}]'}]);
    assert.equal(await store.getValue('workspace'),'[{"path":"restored"}]');
  });
  await test('multi-document mutation is atomic and failed write queue recovers', async () => { db.failKey='fail'; await assert.rejects(store.setValues([{key:'favorites',value:'[]'},{key:'fail',value:'[]'}])); db.failKey=''; assert.equal(await store.getValue('favorites'),'["hash"]'); await store.setValue('ok','[]'); assert.equal(await store.getValue('ok'),'[]'); });
  console.log(`${passed} storage tests passed. (In-memory SDK double; device persistence still requires runtime validation.)`);
})().catch(error => {console.error(error);process.exitCode=1;});
