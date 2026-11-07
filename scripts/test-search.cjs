const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function load(relative) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8');
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    reportDiagnostics: true
  });
  assert.equal(result.diagnostics.length, 0, result.diagnostics.map(item => item.messageText).join('\n'));
  const exports = {};
  vm.runInNewContext(result.outputText, { exports, require(name) { throw Error('Unexpected runtime dependency: ' + name); } });
  return exports;
}

const { ToolRegistry, TOOLS, CATEGORIES } = load('core/ToolRegistry.ets');
const { WorkspaceSearch } = load('core/WorkspaceSearch.ets');
const { HELP_ARTICLES, HELP_SECTIONS } = load('features/help/HelpContent.ets');
const toolIds = query => Array.from(ToolRegistry.search(query), tool => tool.id);
let passed = 0;
function test(name, run) { run(); passed++; console.log('PASS', name); }

test('scene search suggests existing tools and respects categories', () => {
  assert.ok(toolIds('缩小照片').includes('image-compress'));
  assert.ok(toolIds('缩小 照片').includes('image-compress'));
  assert.ok(toolIds('识字').includes('image-ocr'));
  assert.ok(toolIds('合并材料').includes('pdf-merge'));
  assert.ok(toolIds('合并材料').includes('images-pdf'));
  assert.ok(toolIds('报名').includes('image-compress'));
  assert.ok(toolIds('报销').includes('pdf-merge'));
  assert.equal(ToolRegistry.search('报销', 'developer').length, 0);
  assert.ok(Array.from(ToolRegistry.search('报销', 'pdf')).every(tool => tool.category === 'pdf'));
  assert.equal(TOOLS.length, 26);
  assert.equal(CATEGORIES.reduce((sum, category) => sum + category.count, 0), TOOLS.length);
});

test('normal tool search remains case insensitive and unknown scenes do not match all tools', () => {
  assert.ok(toolIds('  JsOn  ').includes('json'));
  assert.ok(toolIds('PDF 合并').includes('pdf-merge'));
  assert.equal(toolIds('   ').length, TOOLS.length);
  assert.equal(toolIds('不存在的场景123').length, 0);
  assert.equal(toolIds('任意上传AI聊天').length, 0);
});

const file = {
  id: 'one', name: '申请表.PDF', path: '/private/workspace/one.pdf', size: 1024,
  mime: 'application/pdf', createdAt: 1, tags: ['待提交', '2026'], collectionId: 'spring'
};
const collections = [{ id: 'spring', name: 'Spring 报名', createdAt: 1 }];

test('workspace search finds names, tags, collection names and terms across fields', () => {
  for (const query of ['申请表', 'pdf', '待提交', '报名', 'SPRING', '  SPRING  2026  ', '申请表 待提交']) {
    assert.ok(WorkspaceSearch.matches(file, query, collections), query);
  }
  assert.ok(!WorkspaceSearch.matches(file, 'Spring 不存在', collections));
  assert.ok(!WorkspaceSearch.matches(file, '/private/workspace', collections));
});

test('workspace empty query and optional metadata behave consistently', () => {
  assert.ok(WorkspaceSearch.matches(file, '\n \t', []));
  assert.ok(!WorkspaceSearch.matches(file, '报名', []));
  const bare = { ...file, tags: undefined, collectionId: undefined };
  assert.ok(WorkspaceSearch.matches(bare, '申请表', collections));
  assert.ok(!WorkspaceSearch.matches(bare, '待提交', collections));
  assert.ok(!WorkspaceSearch.matches(bare, '报名', collections));
  assert.ok(!WorkspaceSearch.matches(file, '.*', collections));
  assert.ok(!WorkspaceSearch.matches({ ...file, collectionId: 'removed' }, 'Spring', collections));
});

test('help keeps nine sections, unique articles, and searchable material and batch instructions', () => {
  assert.equal(HELP_SECTIONS.length, 9);
  assert.equal(new Set(Array.from(HELP_ARTICLES, item => item.id)).size, HELP_ARTICLES.length);
  assert.ok(Array.from(HELP_ARTICLES).every(article => HELP_SECTIONS.some(section => section.id === article.sectionId)));
  const packs = HELP_ARTICLES.find(article => article.id === 'material-packs');
  const batch = HELP_ARTICLES.find(article => article.id === 'workspace-batch');
  assert.ok(packs && packs.matches('清单') && packs.matches('模板'));
  assert.ok(batch && batch.matches('多选') && batch.matches('ZIP'));
  assert.ok(HELP_ARTICLES.find(article => article.id === 'tools').matches('缩小照片'));
});

console.log(`${passed} search and help tests passed.`);
