// Run with Node.js. Uses the TypeScript compiler bundled in DevEco Studio.
// Override LUMIKIT_TYPESCRIPT if the compiler is installed elsewhere.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const Module = require('node:module');
const ts = require(process.env.LUMIKIT_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const filename = require('node:path').join(__dirname, '../main/ets/features/developer/DeveloperUtils.ts');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
}).outputText;
const testModule = new Module(filename, module);
testModule.filename = filename;
testModule.paths = module.paths;
testModule._compile(compiled, filename);
const tools = testModule.exports;
let count = 0;
function check(name, test) {
  test();
  count++;
  console.log(`PASS ${name}`);
}

check('JSON preserves integers larger than the Number safe range', () => {
  assert.match(tools.formatJson('{"id":9007199254740993}'), /9007199254740993/);
  assert.equal(tools.formatJson(' { "id": 9007199254740993 } ', true), '{"id":9007199254740993}');
});
check('JSON formats escaped strings, empty containers and primitive values', () => {
  const raw = JSON.stringify({ text: 'a, b: { "c" }\\\n', empty: {}, arr: [] });
  assert.deepEqual(JSON.parse(tools.formatJson(raw)), JSON.parse(raw));
  assert.equal(tools.formatJson(' null '), 'null');
  assert.equal(tools.formatJson('[]'), '[]');
  assert.equal(tools.formatJson('{}'), '{}');
  assert.equal(tools.formatJson('[1,{"x":2}]'), '[\n  1,\n  {\n    "x": 2\n  }\n]');
  assert.throws(() => tools.formatJson('{"x":}'));
  assert.throws(() => tools.formatJson('['.repeat(129) + '0' + ']'.repeat(129)));
});
check('Base64 round trips UTF-8 and emoji with platform-independent vectors', () => {
  for (const text of ['', 'a', 'ab', 'abc', '你好，集萤 👋', '\u0000\n\r\t', 'é𝌆']) {
    const expected = Buffer.from(text, 'utf8').toString('base64');
    assert.equal(tools.encodeBase64(text), expected);
    assert.equal(tools.decodeBase64(expected), text);
  }
  assert.equal(tools.decodeBase64(' YW Jj \n'), 'abc');
});
check('Base64 rejects malformed input, noncanonical pad bits and invalid UTF-8', () => {
  for (const text of ['a', '=abc', 'YWJj=', '!!!!', 'Zh==', '/w==']) {
    assert.throws(() => tools.decodeBase64(text), text);
  }
});
check('URL uses component encoding and reports malformed escapes', () => {
  assert.equal(tools.convertUrl('a+b c&中文', false), encodeURIComponent('a+b c&中文'));
  assert.equal(tools.convertUrl('a+b%20c', true), 'a+b c');
  assert.throws(() => tools.convertUrl('%GG', true));
});
check('Timestamp handles explicit units, epoch, negative values and timezone', () => {
  assert.equal(tools.convertTimestamp('0').utc, '1970-01-01T00:00:00.000Z');
  assert.equal(tools.convertTimestamp('-1', 'ms').milliseconds, '-1');
  assert.equal(tools.convertTimestamp('-1', 'ms').seconds, '-1');
  assert.equal(tools.convertTimestamp('1700000000000').utc, '2023-11-14T22:13:20.000Z');
  assert.equal(tools.convertTimestamp('2026-10-15 12:00:00+08:00').utc, '2026-10-15T04:00:00.000Z');
  assert.equal(tools.convertTimestamp('2024-02-29T00:00:00Z').utc, '2024-02-29T00:00:00.000Z');
  for (const value of ['2025-02-29 12:00:00', '2026-04-31 12:00:00', '2026-01-01 24:00:00', 'garbage']) {
    assert.throws(() => tools.convertTimestamp(value));
  }
});
check('Color conversion covers HEX, RGB, HSL and invalid components', () => {
  assert.equal(tools.convertColor('#fff').hex, '#FFFFFF');
  assert.equal(tools.convertColor('rgb(255, 0, 0)').hsl, 'hsl(0, 100%, 50%)');
  assert.equal(tools.convertColor('hsl(240, 100%, 50%)').hex, '#0000FF');
  assert.equal(tools.convertColor('hsl(-120, 100%, 50%)').hex, '#0000FF');
  assert.equal(tools.convertColor('#000').hsl, 'hsl(0, 0%, 0%)');
  for (const value of ['#12345', 'rgb(256, 0, 0)', 'hsl(0, 101%, 50%)', 'rgba(1,2,3,.5)']) {
    assert.throws(() => tools.convertColor(value));
  }
});
check('Diff reconstructs both inputs and classifies additions and removals', () => {
  const before = 'one\ntwo\nthree\n';
  const after = 'one\nnew\nthree\nlast';
  const diff = tools.compareLines(before, after);
  assert.equal(diff.filter(line => line.kind !== 'add').map(line => line.text).join('\n'), before);
  assert.equal(diff.filter(line => line.kind !== 'remove').map(line => line.text).join('\n'), after);
  assert.ok(diff.some(line => line.kind === 'remove' && line.text === 'two'));
  assert.ok(diff.some(line => line.kind === 'add' && line.text === 'new'));
  assert.throws(() => tools.compareLines('x\n'.repeat(301), 'x'));
});
check('Regex captures groups, handles zero-length Unicode matches and rejects invalid flags', () => {
  assert.match(tools.testRegex('(a)(b)?', 'g', 'a ab'), /分组 2: 未参与匹配/);
  assert.match(tools.testRegex('(?:)', 'gu', '😀'), /找到 2 项匹配/);
  assert.equal(tools.testRegex('z', '', 'abc'), '没有找到匹配项。');
  assert.throws(() => tools.testRegex('(', '', 'abc'));
  assert.throws(() => tools.testRegex('a', 'gg', 'abc'));
  assert.throws(() => tools.testRegex('', '', 'abc'));
});
check('Markdown renders supported blocks and leaves HTML as inert text', () => {
  const blocks = tools.parseMarkdown('# Title\n\n**bold** and `code`\n\n- item\n> quote\n---\n```ts\n<x>\n```\n<script>alert(1)</script>');
  assert.deepEqual(blocks.map(block => block.kind), ['h1', 'paragraph', 'list', 'quote', 'rule', 'code', 'paragraph']);
  assert.equal(blocks[1].inlines[0].kind, 'bold');
  assert.equal(blocks[5].text, '<x>');
  assert.equal(blocks[6].text, '<script>alert(1)</script>');
});
check('Paste recognition only suggests unambiguous supported structures', () => {
  assert.equal(tools.suggestTool('{"x":1}'), 'json');
  assert.equal(tools.suggestTool('{invalid'), '');
  assert.equal(tools.suggestTool('#123456'), 'color');
  assert.equal(tools.suggestTool('1700000000'), 'timestamp');
  assert.equal(tools.suggestTool('hello'), '');
});
console.log(`${count} developer utility checks passed.`);
