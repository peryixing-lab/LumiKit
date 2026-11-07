const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'lumikit-batch-'));
const ctx = { filesDir: path.join(scratch, 'files'), cacheDir: path.join(scratch, 'cache') };
fs.mkdirSync(ctx.filesDir); fs.mkdirSync(ctx.cacheDir);
const documents = new Map();
const storage = {
  async getValue(key, fallback = '') { return documents.get(key) ?? fallback; },
  async setValue(key, value) { documents.set(key, value); }
};
let pickerUris = [], pickerNames = [], failNative = false, compressed = [], shared = [], copyFailure = '';
const io = {
  OpenMode: { READ_ONLY: fs.constants.O_RDONLY, WRITE_ONLY: fs.constants.O_WRONLY, TRUNC: fs.constants.O_TRUNC, CREATE: fs.constants.O_CREAT },
  accessSync: file => fs.existsSync(file), mkdirSync: (file, recursive) => fs.mkdirSync(file, { recursive: !!recursive }),
  lstatSync: file => fs.lstatSync(file), statSync: file => fs.statSync(file),
  async stat(file) { return fs.statSync(file); },
  async open(file, flags) { return { fd: fs.openSync(file, flags) }; },
  async close(file) { fs.closeSync(file.fd); },
  async copyFile(source, target) {
    if (source === copyFailure) throw Error('injected copy failure');
    if (typeof target === 'number') fs.writeFileSync(target, fs.readFileSync(source));
    else fs.copyFileSync(source, target);
  },
  async unlink(file) { fs.unlinkSync(file); },
  async rmdir(file) { fs.rmSync(file, { recursive: true }); }
};
class FakeSharedData {
  constructor(record) { this.records = [record]; }
  addRecord(record) { this.records.push(record); }
}
const native = {
  '@kit.AbilityKit': {}, '@kit.ArkData': { uniformTypeDescriptor: { UniformDataType: { FILE: 'general.file' } } },
  '@kit.CoreFileKit': { fileIo: io, fileUri: { getUriFromPath: value => 'file://' + value }, picker: { DocumentViewPicker: class {
    async save(options) { pickerNames = options.newFileNames; return pickerUris; }
  } } },
  '@kit.ShareKit': { systemShare: {
    SharedData: FakeSharedData, SharePreviewMode: { DEFAULT: 0 }, SelectionMode: { SINGLE: 0, BATCH: 1 },
    ShareController: class { constructor(data) { this.data = data; } async show(_ctx, options) { shared = [this.data.records, options]; } }
  } },
  '@kit.BasicServicesKit': { zlib: { CompressLevel: { COMPRESS_LEVEL_BEST_SPEED: 1 }, async compressFile(directory, output, options) {
    compressed = fs.readdirSync(directory).map(name => [name, fs.readFileSync(path.join(directory, name), 'utf8')]);
    assert.equal(options.keepTopLevelFolder, false);
    fs.writeFileSync(output, 'native compression test double');
    if (failNative) throw Error('injected archive failure');
  } } }
};
const cache = new Map([[path.join(root, 'core/StorageService.ets'), { StorageService: storage }]]);
function load(relative) {
  const file = path.isAbsolute(relative) ? relative : path.join(root, relative);
  if (cache.has(file)) return cache.get(file);
  const exports = {}; cache.set(file, exports);
  const result = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true });
  assert.equal(result.diagnostics.length, 0);
  vm.runInNewContext(result.outputText, { exports, require: name => native[name] || load(path.resolve(path.dirname(file), name) + '.ets'), Date, Math, Array, Set, Map, JSON, Number, String, Promise, Error });
  return exports;
}
const files = load('core/FileService.ets').FileService;
const { BatchFileService: batch, batchFileNames, batchOutcomeLabel } = load('core/BatchFileService.ets');
const plain = value => JSON.parse(JSON.stringify(value));
let passed = 0;
async function test(name, run) { await run(); passed++; console.log('PASS', name); }
async function make(name, content = 'fixture') {
  const file = files.outputPath(ctx, name); fs.writeFileSync(file, content); return files.register(ctx, file, name);
}
(async () => {
  const first = await make('票据.pdf', 'first'), second = await make('票据.pdf', 'second');
  await test('delivery names sanitize separators, handle dot paths and deduplicate case-insensitively', () => {
    assert.deepEqual(plain(batchFileNames([{ name: '票据.pdf' }, { name: '票据.pdf' }, { name: 'a/b.txt' }, { name: 'A_B.TXT' }, { name: '..' }])), ['票据.pdf', '票据_2.pdf', 'a_b.txt', 'A_B_2.TXT', 'document']);
    const names = batchFileNames([{name: 'a.' + 'b'.repeat(118)}, {name: 'a.' + 'b'.repeat(118)}]);
    assert.ok(names.every(name => name.length <= 120)); assert.notEqual(names[0], names[1]);
  });
  await test('multi-file export preserves ordering and uses the chosen safe file names', async () => {
    pickerUris = [path.join(scratch, 'export1'), path.join(scratch, 'export2')]; pickerUris.forEach(file => fs.writeFileSync(file, ''));
    await batch.exportFiles(ctx, [first, second]);
    assert.deepEqual(plain(pickerNames), ['票据.pdf', '票据_2.pdf']);
    assert.equal(fs.readFileSync(pickerUris[0], 'utf8'), 'first'); assert.equal(fs.readFileSync(pickerUris[1], 'utf8'), 'second');
  });
  await test('cancellation and count mismatch never map a file to a wrong output', async () => {
    pickerUris = []; await assert.rejects(batch.exportFiles(ctx, [first]), /取消/);
    pickerUris = [path.join(scratch, 'untouched')]; fs.writeFileSync(pickerUris[0], 'keep');
    await assert.rejects(batch.exportFiles(ctx, [first, second]), /数量不匹配/);
    assert.equal(fs.readFileSync(pickerUris[0], 'utf8'), 'keep');
  });
  await test('partial export failure reports completed and failed counts and preserves originals', async () => {
    pickerUris = [path.join(scratch, 'partial1'), path.join(scratch, 'partial2')]; pickerUris.forEach(file => fs.writeFileSync(file, ''));
    copyFailure = second.path; await assert.rejects(batch.exportFiles(ctx, [first, second]), /成功 1 个，未完成 1 个/); copyFailure = '';
    assert.equal(fs.readFileSync(first.path, 'utf8'), 'first'); assert.equal(fs.readFileSync(second.path, 'utf8'), 'second');
  });
  await test('native share uses BATCH mode and physical copies named for delivery', async () => {
    await batch.share(ctx, [first, second]); assert.equal(shared[1].selectionMode, 1); assert.equal(shared[0].length, 2);
    const target = shared[0][1].uri.replace('file://', '');
    assert.equal(path.basename(target), '票据_2.pdf'); assert.equal(fs.readFileSync(target, 'utf8'), 'second');
    assert.ok(fs.existsSync(target)); assert.notEqual(target, second.path);
    const shares = fs.readdirSync(ctx.cacheDir).filter(name => name.startsWith('lumi_share_')).length;
    copyFailure = second.path; await assert.rejects(batch.share(ctx, [first, second]), /copy failure/); copyFailure = '';
    assert.equal(fs.readdirSync(ctx.cacheDir).filter(name => name.startsWith('lumi_share_')).length, shares);
  });
  await test('archives copy safe distinct names, register provenance, and always clean staging', async () => {
    const archive = await batch.archive(ctx, [first, second], '材料.zip');
    assert.equal(archive.name, '材料.zip'); assert.equal(archive.mime, 'application/zip');
    assert.deepEqual(plain(compressed), [['票据.pdf', 'first'], ['票据_2.pdf', 'second']]);
    assert.deepEqual(plain(archive.sourcePaths), [first.path, second.path]); assert.equal(archive.role, 'final');
    assert.equal(fs.readdirSync(ctx.cacheDir).filter(name => name.startsWith('lumi_archive_')).length, 0);
    const count = (await files.list(ctx)).length;
    failNative = true; await assert.rejects(batch.archive(ctx, [first], '失败.zip'), /archive failure/); failNative = false;
    assert.equal((await files.list(ctx)).length, count); assert.equal(fs.readdirSync(ctx.cacheDir).filter(name => name.startsWith('lumi_archive_')).length, 0);
    assert.ok(!fs.readdirSync(files.directory(ctx)).some(name => name.endsWith('失败.zip')));
  });
  await test('material-bound files survive batch trash while unrelated files succeed', async () => {
    documents.set('material.packs', JSON.stringify([{ entries: [{ filePath: first.path }] }]));
    const outcome = await batch.organize(ctx, [first, second], 'trash');
    assert.deepEqual(plain(outcome.succeeded), [second.path]); assert.equal(outcome.failed.length, 1); assert.match(outcome.failed[0].reason, /材料包/);
    assert.match(batchOutcomeLabel(outcome), /票据.pdf/); assert.ok((await files.list(ctx)).some(file => file.path === first.path));
    const restored = await batch.organize(ctx, [second], 'restore'); assert.equal(restored.succeeded.length, 1);
    documents.delete('material.packs');
  });
  await test('batch tagging appends deduplicated tags without silently dropping excess tags', async () => {
    await batch.organize(ctx, [first], 'tags', [' 报销 ', '报销']);
    let current = (await files.list(ctx)).find(file => file.path === first.path); assert.deepEqual(plain(current.tags), ['报销']);
    current.tags = Array.from({ length: 10 }, (_value, index) => String(index)); await files.updateDetails(ctx, current);
    const outcome = await batch.organize(ctx, [first], 'tags', ['超出']); assert.equal(outcome.failed.length, 1);
    assert.equal((await files.list(ctx)).find(file => file.path === first.path).tags.length, 10);
  });
  await test('delivery rejects duplicate paths, trashed sources and over-count requests before opening picker', async () => {
    await assert.rejects(batch.share(ctx, [first, first]), /重复/);
    await assert.rejects(batch.share(ctx, Array(101).fill(first)), /100/);
    await files.setTrash(ctx, second, true); await assert.rejects(batch.share(ctx, [second]), /已移除/);
  });
  await test('delivery checks current byte size before calling a native share or picker', async () => {
    fs.truncateSync(first.path, 501 * 1024 * 1024);
    await assert.rejects(batch.share(ctx, [first]), /500 MB/);
    fs.writeFileSync(first.path, 'first');
  });
  console.log(`${passed} batch-file tests passed. SDK share, picker and ZIP encoding require device validation.`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => fs.rmSync(scratch, { recursive: true, force: true }));
