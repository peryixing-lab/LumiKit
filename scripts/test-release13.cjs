const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const sdk = process.env.HARMONY_SDK_HOME || '/Applications/DevEco-Studio.app/Contents/sdk/default';
const ts = require(path.join(sdk, 'openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const settings = new Map();
let rejectExport = false;
let finishExport;
const fileService = {
  assertOwned(_ctx, filePath) { if (!filePath.startsWith('/workspace/')) throw Error('invalid path'); },
  async exportFile() {
    if (rejectExport) throw Error('已取消导出');
    if (finishExport) await finishExport;
    return 'file://selected-location';
  }
};
const storage = {getSetting: async (key, fallback) => settings.get(key) ?? fallback,
  setSetting: async (key, value) => settings.set(key, value)};
function load(name) {
  const exports = {};
  const source = fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/core', name + '.ets'), 'utf8');
  const code = ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021}}).outputText;
  vm.runInNewContext(code, {exports, require: name => name.endsWith('/StorageService') ? {StorageService: storage} : {FileService: fileService}});
  return exports;
}
const incomingModule = load('IncomingActions');
const incoming = incomingModule.lumiIncomingActions;
const delivery = load('BackupDelivery').BackupDelivery;
const file = (name, mime) => ({name, mime, path: '/workspace/' + name});
const ids = files => Array.from(incoming(files), action => action.toolId);
let passed = 0;
async function test(name, run) { await run(); passed++; console.log('PASS', name); }
(async () => {
  await test('incoming images offer purpose choices; multi-image OCR is not falsely offered', () => {
    assert.deepEqual(ids([file('photo.jpg', 'image/jpeg')]), ['image-compress', 'images-pdf', 'image-ocr', 'file-workspace']);
    assert.deepEqual(ids([file('1.png', 'image/png'), file('2.jpg', 'image/jpeg')]), ['image-compress', 'images-pdf', 'file-workspace']);
  });
  await test('incoming PDFs and spreadsheets offer operations that accept their file count', () => {
    assert.deepEqual(ids([file('a.pdf', 'application/pdf')]), ['pdf-compress', 'pdf-edit', 'file-workspace']);
    assert.deepEqual(ids([file('a.pdf', 'application/pdf'), file('b.pdf', 'application/pdf')]), ['pdf-merge', 'file-workspace']);
    assert.deepEqual(ids([file('a.XLSX', 'application/octet-stream')]), ['analytics', 'file-workspace']);
    assert.deepEqual(ids([file('a.csv', 'text/csv')]), ['analytics', 'file-workspace']);
  });
  await test('mixed and unsupported inputs stay in workspace and input ordering is untouched', () => {
    const files = [file('a.pdf', 'application/pdf'), file('b.png', 'image/png')];
    const snapshot = JSON.stringify(files);
    assert.deepEqual(ids(files), ['file-workspace']); assert.deepEqual(ids([]), []);
    assert.equal(JSON.stringify(files), snapshot);
  });
  await test('incoming page order follows the sender instead of newest-first catalog ordering', () => {
    const first = file('first.png', 'image/png'), second = file('second.png', 'image/png');
    const trashed = {...file('removed.png', 'image/png'), trashedAt: 1};
    const resolved = incomingModule.lumiIncomingFiles([first.path, second.path, first.path, trashed.path, '/missing'], [trashed, second, first]);
    assert.deepEqual(Array.from(resolved, entry => entry.name), ['first.png', 'second.png']);
  });
  await test('new generation is persisted separately from successful external export', async () => {
    const generated = await delivery.generated(file('backup.lumibak', 'application/octet-stream'));
    assert.ok(generated.generatedAt > 0); assert.equal(generated.exportedAt, 0);
    assert.equal((await delivery.load()).path, generated.path);
    let release;
    finishExport = new Promise(resolve => {release = resolve;});
    const pending = delivery.exportPending({}, generated);
    await Promise.resolve();
    assert.equal((await delivery.load()).exportedAt, 0);
    release(); const exported = await pending; finishExport = undefined;
    assert.ok(exported.exportedAt >= generated.generatedAt);
    assert.equal(generated.exportedAt, 0, 'caller snapshot is never mutated before persistence');
    assert.equal((await delivery.load()).lastExportedName, 'backup.lumibak');
  });
  await test('cancelled export remains resumable across reload and preserves previous export record', async () => {
    const previous = await delivery.load();
    const generated = await delivery.generated(file('next.lumibak', 'application/octet-stream'));
    rejectExport = true;
    await assert.rejects(delivery.exportPending({}, generated), /已取消导出/);
    const restored = await delivery.load();
    assert.equal(restored.exportedAt, 0); assert.equal(restored.path, generated.path);
    assert.equal(restored.lastExportedAt, previous.lastExportedAt);
    assert.equal(restored.lastExportedName, 'backup.lumibak');
    rejectExport = false;
    await delivery.exportPending({}, restored);
    assert.equal((await delivery.load()).lastExportedName, 'next.lumibak');
  });
  await test('missing and malformed backup delivery state never claim an export', async () => {
    for (const content of ['', 'not json', 'null', '{}', '{"generatedAt":-1}']) {
      settings.set('backup.delivery', content);
      const state = await delivery.load(); assert.equal(state.exportedAt, 0); assert.equal(state.path, '');
    }
    await assert.rejects(delivery.exportPending({}, {path: '/outside/private', name: 'bad.lumibak'}), /invalid path/);
  });
  console.log(`${passed} release 1.3 delivery checks passed. Native picker/share behavior needs device validation.`);
})().catch(error => {console.error(error); process.exitCode = 1;});
