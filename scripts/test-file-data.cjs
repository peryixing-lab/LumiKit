/** Run with DevEco's Node: node scripts/test-file-data.cjs. No device or dependencies to install. */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const sdk = process.env.HARMONY_SDK_HOME || '/Applications/DevEco-Studio.app/Contents/sdk/default';
const ts = require(path.join(sdk, 'openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = path.join(__dirname, '../entry/src/main/ets/features/files/DataEngine.ets');
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
const sandbox = { exports: {} };
vm.runInNewContext(code, sandbox);
const DataEngine = sandbox.exports.DataEngine;
const plain = value => JSON.parse(JSON.stringify(value));
let passed = 0;
function test(name, run) { run(); passed++; console.log('PASS', name); }

test('BOM, CRLF, quoted commas, escaped quotes, and quoted newlines', () => {
  const table = DataEngine.parseCSV('\ufeff姓名,备注,金额\r\n小林,"逗号,引号""与\n换行",0012\r\n小吴,,0\r\n');
  assert.deepEqual(plain(table.rows), [['小林', '逗号,引号"与\n换行', '0012'], ['小吴', '', '0']]);
  assert.deepEqual(plain(DataEngine.parseCSV(DataEngine.csv(table))), plain(table));
  assert.equal(JSON.parse(DataEngine.json(table))[0]['金额'], '0012');
});
test('headers become nonempty and unique', () => {
  assert.deepEqual(plain(DataEngine.parseCSV('a,a,\n1,2,3').headers), ['a', 'a_2', '字段3']);
});
test('JSON flat primitives, null, missing values, and numeric strings', () => {
  assert.deepEqual(plain(DataEngine.fromJSON('[{"a":1,"b":null},{"b":false,"c":"01"}]')), {
    headers: ['a', 'b', 'c'], rows: [['1', '', ''], ['', 'false', '01']]
  });
});
test('reserved property names survive CSV to JSON', () => {
  const data = JSON.parse(DataEngine.json(DataEngine.parseCSV('__proto__,constructor\nkept,also kept')));
  assert.equal(data[0].__proto__, 'kept');
  assert.equal(data[0].constructor, 'also kept');
});
test('malformed CSV is rejected', () => {
  for (const input of ['a\n"unclosed', 'a\n"done"bad', 'a\n1,2']) { assert.throws(() => DataEngine.parseCSV(input)); }
});
test('nested/non-object/empty JSON is rejected', () => {
  for (const input of ['[{"a":{"nested":1}}]', '[1,2]', '[]']) { assert.throws(() => DataEngine.fromJSON(input)); }
});
test('row and column limits cover unterminated final records', () => {
  assert.throws(() => DataEngine.parseCSV(Array.from({ length: 101 }, (_, i) => 'h' + i).join(',')));
  assert.throws(() => DataEngine.parseCSV('header\n' + Array.from({ length: 20001 }, () => 'value').join('\n')));
});
test('numeric summary skips blank and nonnumeric cells', () => {
  assert.deepEqual(plain(DataEngine.summary({ headers: ['n'], rows: [['12'], [''], ['oops'], ['-4'], ['0']] }, 0)), {
    count: 3, empty: 1, sum: 8, mean: 8 / 3, min: -4, max: 12
  });
});
test('group count and sum include null groups', () => {
  assert.deepEqual(plain(DataEngine.groups({ headers: ['g', 'v'], rows: [['A', '3'], ['A', '4'], ['B', 'x'], ['', '2']] }, 0, 1)), [
    { label: 'A', count: 2, sum: 7 }, { label: 'B', count: 1, sum: 0 }, { label: '', count: 1, sum: 2 }
  ]);
});
test('literal empty label and actual blank group stay distinct', () => {
  const groups = DataEngine.groups({ headers: ['g', 'v'], rows: [['（空值）', '1'], ['', '2']] }, 0, 1);
  assert.equal(groups.length, 2);
});
const nativeSource = path.join(__dirname, '../entry/src/main/ets/features/files/NativeFileOperations.ets');
const nativeCode = ts.transpileModule(fs.readFileSync(nativeSource, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
}).outputText;
// SDK modules are deliberately stubbed: only the pure page-range parser is exercised here.
const nativeSandbox = { exports: {}, require: () => ({}) };
vm.runInNewContext(nativeCode, nativeSandbox);
const parsePages = nativeSandbox.exports.parsePages;
test('page ranges validate, deduplicate, and preserve source order', () => {
  assert.deepEqual(plain(parsePages('5,1-3,2', 6)), [0, 1, 2, 4]);
  assert.deepEqual(plain(parsePages('', 3)), [0, 1, 2]);
  for (const value of ['0', '7', '3-1', '1-', '1,,2', 'NaN']) { assert.throws(() => parsePages(value, 6)); }
});
console.log(`${passed} data tests passed.`);

// Exercise the real shared catalog and path guards with a filesystem adapter and in-memory metadata.
(async () => {
  const os = require('node:os');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lumikit-catalog-'));
  const dir = path.join(root, 'workspace'); fs.mkdirSync(dir);
  const documents = new Map();
  const storage = { getValue: async (key, fallback = '') => documents.get(key) || fallback,
    setValue: async (key, value) => { documents.set(key, value); } };
  const adapter = { accessSync: fs.existsSync, lstatSync: fs.lstatSync, statSync: fs.statSync,
    unlink: fs.promises.unlink };
  const fileSource = path.join(__dirname, '../entry/src/main/ets/core/FileService.ets');
  const fileCode = ts.transpileModule(fs.readFileSync(fileSource, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const fileSandbox = { exports: {}, require: name => name === '@kit.CoreFileKit' ? { fileIo: adapter } :
    name === './StorageService' ? { StorageService: storage } : {} };
  vm.runInNewContext(fileCode, fileSandbox);
  const Files = fileSandbox.exports.FileService;
  const context = { filesDir: root };
  const check = async (name, run) => { await run(); passed++; console.log('PASS', name); };
  try {
    await check('workspace path boundary rejects traversal, nested paths, and symbolic links', async () => {
      assert.equal(Files.isOwnedPath(context, path.join(dir, 'valid.csv')), true);
      for (const value of [path.join(root, 'outside'), dir + '/../outside', dir + '/nested/file', dir + '/..']) {
        assert.equal(Files.isOwnedPath(context, value), false);
      }
      fs.writeFileSync(path.join(root, 'outside'), 'private');
      fs.symlinkSync(path.join(root, 'outside'), path.join(dir, 'link'));
      assert.throws(() => Files.assertOwned(context, path.join(dir, 'link')));
    });
    await check('concurrent catalog registrations preserve every result', async () => {
      const registrations = [];
      for (let index = 0; index < 10; index++) {
        const file = path.join(dir, `output_${index}.csv`); fs.writeFileSync(file, 'header\nvalue');
        registrations.push(Files.register(context, file, `output_${index}.csv`));
      }
      await Promise.all(registrations);
      assert.equal((await Files.list(context)).length, 10);
    });
    await check('saved attachments cannot be deleted from the shared workspace', async () => {
      const file = (await Files.list(context))[0];
      documents.set('inventory.items', JSON.stringify([{ attachments: [{ path: file.path }] }]));
      await assert.rejects(() => Files.remove(context, file));
      assert.equal(fs.existsSync(file.path), true);
      documents.delete('inventory.items');
      await Files.remove(context, file);
      assert.equal(fs.existsSync(file.path), true);
      assert.equal((await Files.list(context)).length, 9);
      assert.equal((await Files.list(context, true)).length, 10);
      await Files.setTrash(context, file, false);
      assert.equal((await Files.list(context)).length, 10);
      await assert.rejects(() => Files.deletePermanently(context, file));
      await Files.remove(context, file);
      await Files.deletePermanently(context, file);
      assert.equal(fs.existsSync(file.path), false);
      assert.equal((await Files.list(context, true)).length, 9);
    });
    await check('restored invalid workspace paths are filtered', async () => {
      documents.set('workspace', JSON.stringify([{ id: 'outside', name: 'outside', path: path.join(root, 'outside') }, null]));
      assert.equal((await Files.list(context)).length, 0);
    });
  } finally { fs.rmSync(root, { recursive: true, force: true }); }
  console.log(`${passed} total data and catalog tests passed.`);
})().catch(error => { console.error(error); process.exitCode = 1; });
