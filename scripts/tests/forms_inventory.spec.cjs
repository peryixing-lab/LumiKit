// Run: node scripts/tests/forms_inventory.spec.cjs
// Uses DevEco Studio's bundled compiler; override LUMIKIT_TYPESCRIPT if needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LUMIKIT_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '../..');
function load(relative, modules = {}) {
  const filename = path.join(root, relative);
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, reportDiagnostics: true
  });
  assert.equal(result.diagnostics.length, 0, result.diagnostics.map(item => item.messageText).join('\n'));
  const exports = {};
  vm.runInNewContext(result.outputText, { exports, require: name => modules[name], Date, Math, Number, Array, JSON });
  return exports;
}
const inventory = load('entry/src/main/ets/features/inventory/InventoryModels.ets');
const forms = load('entry/src/main/ets/features/forms/FormModels.ets', { '../inventory/InventoryModels': inventory });
const print = load('entry/src/main/ets/features/forms/FormPrintLayout.ets', {
  './FormModels': forms, '../inventory/InventoryModels': inventory
});
let checks = 0;
function check(name, test) { test(); checks++; console.log(`PASS ${name}`); }
check('dates reject impossible days, accept leap years and round trip local dates', () => {
  assert.ok(inventory.isValidDate('2024-02-29'));
  for (const value of ['2025-02-29', '2026-13-01', '2026-04-31', '26-01-01', '2026-01-00', '2026-1-1']) {
    assert.ok(!inventory.isValidDate(value), value);
  }
  assert.equal(inventory.localDate(new Date(2026, 9, 15)), '2026-10-15');
});
const form = new forms.LocalForm(); form.id = 'test'; form.title = '登记';
const text = new forms.FormField(); text.id = 'name'; text.label = '姓名'; text.required = true;
const choice = new forms.FormField(); choice.id = 'topics'; choice.type = 'checkbox'; choice.label = '兴趣';
choice.options = ['摄影', '阅读']; choice.defaultValue = '摄影|阅读'; choice.required = true;
const rating = new forms.FormField(); rating.id = 'rating'; rating.type = 'rating'; rating.label = '评分'; rating.defaultValue = '4';
form.fields = [text, choice, rating];
check('JSON Schema carries mandatory fields, choice arrays, integer ratings and defaults', () => {
  const schema = JSON.parse(JSON.stringify(forms.buildJsonSchema(form)));
  assert.equal(schema.$schema, 'https://json-schema.org/draft/2020-12/schema');
  assert.deepEqual(schema.required, ['name', 'topics']);
  assert.equal(schema.properties.topics.type, 'array');
  assert.equal(schema.properties.topics.minItems, 1);
  assert.deepEqual(schema.properties.topics.items.enum, ['摄影', '阅读']);
  assert.deepEqual(schema.properties.topics.default, ['摄影', '阅读']);
  assert.equal(schema.properties.rating.type, 'integer');
  assert.equal(schema.properties.rating.default, 4);
  assert.equal(schema.properties.rating.minimum, 1);
  assert.equal(schema.properties.rating.maximum, 5);
  assert.equal(schema.additionalProperties, false);
});
check('CSV quotes commas, double quotes and newlines and neutralizes formula cells', () => {
  assert.equal(forms.csvCell('a,"b"\nc'), '"a,""b""\nc"');
  for (const value of ['=1+1', '+1+1', '-1+1', '@SUM(A1)', '\tcmd']) {
    assert.equal(forms.csvCell(value), `"'${value}"`);
  }
});
const response = new forms.FormResponse(); response.formId = form.id; response.formTitle = form.title;
response.submittedAt = '2026-10-15 12:00:00';
const oldAnswer = new forms.FieldAnswer(); oldAnswer.fieldId = 'deleted'; oldAnswer.label = '旧问题'; oldAnswer.value = '旧回答';
response.answers = [oldAnswer];
check('CSV exports preserve answers from removed fields and UTF-8 BOM', () => {
  const csv = forms.responseCsv(form, [response]);
  assert.ok(csv.startsWith('\uFEFF'));
  assert.ok(csv.includes('旧问题（历史字段）'));
  assert.ok(csv.includes('旧回答'));
  assert.equal(csv.split('\r\n').length, 2);
});
check('restored metadata validates shapes before rendering', () => {
  assert.ok(forms.validForm(form));
  assert.ok(forms.validResponse(response));
  assert.ok(!forms.validForm(null));
  assert.ok(!forms.validResponse({ answers: [{}] }));
  assert.ok(inventory.validInventoryItem(new inventory.InventoryItem()));
  assert.ok(!inventory.validInventoryItem({ id: 'bad', attachments: [] }));
});
const measure = (value, size) => Array.from(value).reduce((width, char) => width + (char.charCodeAt(0) > 127 ? size : size * .6), 0);
check('PDF wrapping retains Unicode code points, paragraphs and every text character', () => {
  const value = '中文😀 mixed long text and spaces'.repeat(20);
  const lines = print.wrapPrintText(value, 140, 11, false, measure);
  assert.equal(lines.join(''), value);
  assert.ok(lines.every(line => measure(line, 11) <= 140));
  assert.equal(Array.from(print.wrapPrintText('a\nb\n', 100, 11, false, measure)).join('|'), 'a|b|');
});
check('print layout paginates at A4 safe height without dropping or duplicating lines', () => {
  const large = new forms.LocalForm(); large.title = '长表单';
  for (let index = 0; index < 90; index++) {
    const field = new forms.FormField(); field.id = `field_${index}`; field.label = `字段 ${index}`;
    field.type = forms.FIELD_TYPES[index % forms.FIELD_TYPES.length]; field.options = ['选项一', '选项二'];
    large.fields.push(field);
  }
  const lines = print.formPrintLines(large, undefined, measure);
  const pages = print.paginatePrintLines(lines);
  assert.ok(pages.length > 1);
  assert.equal(pages.flat().length, lines.length);
  assert.equal(pages.flat().map(line => line.text).join('\n'), lines.map(line => line.text).join('\n'));
  assert.ok(pages.every(page => page.reduce((height, line) => height + line.size * 1.6 + line.gap, 0) <= 720));
});
check('filled PDF reads saved historical answers instead of current field definitions', () => {
  const lines = print.formPrintLines(form, response, measure).map(line => line.text).join('\n');
  assert.ok(lines.includes('旧问题') && lines.includes('旧回答'));
  assert.ok(lines.includes(response.submittedAt));
  assert.ok(!lines.includes('________'));
});
check('PDF applies explicit field and text limits before native generation', () => {
  const large = new forms.LocalForm(); large.title = '上限验证';
  large.fields = Array.from({ length: 151 }, () => new forms.FormField());
  assert.throws(() => print.formPrintLines(large, undefined, measure), /150/);
  large.fields = [];
  large.description = 'x'.repeat(30001);
  assert.throws(() => print.formPrintLines(large, undefined, measure), /3 万字/);
});
console.log(`${checks} inventory/forms model and PDF layout checks passed.`);
