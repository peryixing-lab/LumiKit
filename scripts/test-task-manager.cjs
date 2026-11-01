/** Durable task lifecycle tests. No HarmonyOS device APIs are simulated as successful file operations. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const sdk = process.env.HARMONY_SDK_HOME || '/Applications/DevEco-Studio.app/Contents/sdk/default';
const ts = require(path.join(sdk, 'openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/core/TaskManager.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const documents = new Map();
let clock = 100000;
let writes = 0;
let failRead = false;
const storage = {
  getValue: async (key, fallback = '') => { if (failRead) { throw Error('read unavailable'); } return documents.get(key) || fallback; },
  setValue: async (key, value) => { documents.set(key, value); writes++; }
};
const sandbox = { exports: {}, Date: { now: () => clock }, require: name => name === '@kit.ArkTS' ?
  { util: { generateRandomUUID: () => crypto.randomUUID() } } : { StorageService: storage } };
vm.runInNewContext(code, sandbox);
const Tasks = sandbox.exports.TaskManager;
let passed = 0;
async function test(name, run) { await run(); passed++; console.log('PASS', name); }
const get = async id => (await Tasks.list()).find(record => record.id === id);

(async () => {
  await test('pending, running, progress, and completed state are persisted', async () => {
    const id = await Tasks.begin('pdf-split', '拆分 PDF', ['/private/workspace/input.pdf']);
    assert.equal((await get(id)).state, 'pending');
    await Tasks.running(id); await Tasks.progress(id, 35);
    assert.equal((await get(id)).state, 'running'); assert.equal((await get(id)).progress, 35);
    await Tasks.complete(id, ['/private/workspace/page_1.pdf']);
    assert.equal((await get(id)).state, 'completed'); assert.equal((await get(id)).progress, 100);
    assert.equal((await get(id)).outputPaths[0], '/private/workspace/page_1.pdf');
    await Tasks.progress(id, 90); await Tasks.fail(id, 'late callback');
    assert.equal((await get(id)).state, 'completed');
  });
  await test('progress writes are throttled and cannot go backwards', async () => {
    const id = await Tasks.begin('image-convert', '图片格式转换', []); await Tasks.running(id);
    const before = writes; await Tasks.progress(id, 20); await Tasks.progress(id, 40);
    assert.equal(writes - before, 1); assert.equal((await get(id)).progress, 20);
    clock += 600; await Tasks.progress(id, 10); assert.equal((await get(id)).progress, 20);
  });
  await test('explicit cancellation is terminal', async () => {
    const id = await Tasks.begin('images-pdf', '图片转 PDF', []); await Tasks.running(id);
    await Tasks.fail(id, '用户已取消任务', true); await Tasks.complete(id, []); await Tasks.progress(id, 100);
    assert.equal((await get(id)).state, 'cancelled');
  });
  await test('startup recovery fails interrupted tasks and retains terminal records', async () => {
    const pending = await Tasks.begin('pdf-merge', '合并 PDF', []);
    const running = await Tasks.begin('pdf-images', 'PDF 转图片', []); await Tasks.running(running);
    await Tasks.recoverInterrupted();
    assert.equal((await get(pending)).state, 'failed'); assert.match((await get(pending)).error, /重试/);
    assert.equal((await get(running)).state, 'failed');
    assert.ok((await Tasks.list()).some(record => record.state === 'completed'));
  });
  await test('parallel changes keep the latest 100 task records', async () => {
    await Promise.all(Array.from({ length: 105 }, (_, index) => Tasks.begin('image-convert', '任务 ' + index, [])));
    const list = await Tasks.list(); assert.equal(list.length, 100); assert.equal(new Set(list.map(record => record.id)).size, 100);
  });
  await test('runtime validation drops malformed records and unknown payload fields', async () => {
    const valid = (await Tasks.list())[0]; valid.password = 'never retain'; valid.inputBody = 'never retain';
    documents.set('tasks', JSON.stringify([null, { id: 'bad', state: 'other' }, valid, valid]));
    const list = await Tasks.list(); assert.equal(list.length, 1);
    assert.equal(Object.hasOwn(list[0], 'password'), false); assert.equal(Object.hasOwn(list[0], 'inputBody'), false);
    await Tasks.recoverInterrupted(); assert.equal(documents.get('tasks').includes('never retain'), false);
  });
  await test('storage read failures do not silently replace previous records', async () => {
    const original = documents.get('tasks'); failRead = true;
    await assert.rejects(() => Tasks.begin('pdf-split', '拆分 PDF', []));
    assert.equal(documents.get('tasks'), original); failRead = false;
    assert.equal((await Tasks.list()).length, 1);
  });
  console.log(`${passed} durable task tests passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
