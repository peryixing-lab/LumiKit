#!/usr/bin/env python3
"""Real UI checks for LumiKit inventory/forms. Creates and deletes only uniquely named QA records.

Requires a rebuilt app containing the semantic IDs in InventoryPage/FormsPage and an already running
app at its main tabs. This script does not build, install, clear data, or directly edit app databases.
Only keyboard Back/Ctrl+A use the same UITest key helper as emulator-check.py; inspection, taps,
text, swipes and screenshots use DevEco CLI. Do not run concurrently with another UI controller.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timedelta
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
NODE = '/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node'
CLI = '/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js'
HDC = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'


def flatten(data):
    if isinstance(data, list):
        return [node for child in data for node in flatten(child)]
    if not isinstance(data, dict):
        return []
    return [data] + [node for child in data.get('children', []) for node in flatten(child)]


class BusinessCheck:
    def __init__(self, args):
        self.args = args
        self.out = (ROOT / args.output).resolve()
        self.out.mkdir(parents=True, exist_ok=True)
        self.run_id = datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y%m%d-%H%M%S')
        self.item_name = f'QA-LumiKit-{self.run_id}-Item'
        self.edited_name = self.item_name + '-E'
        self.form_name = f'QA-LumiKit-{self.run_id}-Form'
        self.pdf_names = [self.form_name + '_空白模板.pdf', self.form_name + '_回答.pdf']
        self.safe_top = int(args.height * (320 / 2848))
        self.safe_bottom = int(args.height * (2650 / 2848))
        self.report = {
            'runId': self.run_id, 'device': args.device, 'startedAt': datetime.now().astimezone().isoformat(),
            'qaNames': {'item': self.item_name, 'editedItem': self.edited_name, 'form': self.form_name},
            'steps': [], 'findings': [], 'created': [], 'deleted': [], 'pdfEvidence': [],
            'status': 'running',
            'notes': ['No existing records or application history are cleared.',
                      'QA history entries remain because the UI has no per-record history deletion.']
        }
        self.flush()

    def flush(self):
        (self.out / 'business-results.json').write_text(json.dumps(self.report, ensure_ascii=False, indent=2))

    def cmd(self, *parts, timeout=30):
        proc = subprocess.run([NODE, CLI, *map(str, parts), '--device', self.args.device], cwd=ROOT,
                              text=True, capture_output=True, timeout=timeout)
        if proc.returncode:
            raise RuntimeError((proc.stdout + proc.stderr)[-2400:])
        return proc.stdout

    def key(self, *keys):
        subprocess.run([HDC, '-t', self.args.device, 'shell', 'uitest', 'uiInput', 'keyEvent', *map(str, keys)],
                       cwd=ROOT, text=True, capture_output=True, check=True, timeout=15)
        time.sleep(.3)

    def restart_app(self):
        # All callers have just saved this run's QA record; no unknown draft is abandoned.
        for parts in [('aa', 'force-stop', 'com.lovexjy.LumiKit'),
                      ('aa', 'start', '-b', 'com.lovexjy.LumiKit', '-a', 'EntryAbility', '-m', 'entry')]:
            proc = subprocess.run([HDC, '-t', self.args.device, 'shell', *parts], cwd=ROOT, text=True,
                                  capture_output=True, check=True, timeout=20)
            if re.search(r'\b(error|failed|failure)\b', proc.stdout + proc.stderr, re.I):
                raise RuntimeError('App restart failed: ' + (proc.stdout + proc.stderr)[-1600:])
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                if self.find_id('nav-tab-0'):
                    return
            except (RuntimeError, json.JSONDecodeError):
                pass
            time.sleep(.5)
        raise AssertionError('App did not return to main tabs after a real process restart')

    def layout(self):
        return json.loads(self.cmd('ui', 'layout', '--format', 'json', '--mode', 'full'))

    def nodes(self):
        return flatten(self.layout())

    def alltext(self):
        return '\n'.join(str(node.get('text', '')) for node in self.nodes())

    def find_id(self, key):
        return next((node for node in self.nodes() if node.get('id') == key), None)

    def find_text(self, text):
        return next((node for node in self.nodes() if node.get('text') == text), None)

    def tap(self, node):
        bounds = node.get('bounds')
        if not isinstance(bounds, list) or len(bounds) != 4:
            raise RuntimeError('Visible node has no usable bounds: ' + str(node.get('id', node.get('text', ''))))
        x = (bounds[0] + bounds[2]) // 2
        y = (bounds[1] + bounds[3]) // 2
        nav = str(node.get('id', '')).startswith('nav-tab-')
        if not self.clickable_bounds(node, nav):
            raise AssertionError('Refusing a tap outside the screenshot safe area: ' + str(bounds))
        if self.report['steps']:
            self.report['steps'][-1].setdefault('targets', []).append({
                'id': node.get('id'), 'text': node.get('text'), 'bounds': bounds, 'center': [x, y],
                'safeArea': [0, 0 if nav else self.safe_top, self.args.width, self.args.height if nav else self.safe_bottom],
                'fullyWithinSafeArea': True, 'navigationException': nav})
        self.cmd('ui', 'click', x, y)
        time.sleep(.3)

    def swipe(self, direction):
        # The right-side Scroll gutter avoids TextArea and horizontal-table gesture capture.
        # Do not use max(node.bounds): UI trees can include off-screen content taller than the display.
        width, height = self.args.width, self.args.height
        x = max(1, width - 20)
        upper, lower = int(height * .20), int(height * .84)
        start, end = (lower, upper) if direction == 'up' else (upper, lower)
        self.cmd('ui', 'swipe', x, start, x, end, '--speed', 2000)
        time.sleep(.35)

    def signature(self):
        return [(node.get('id', ''), node.get('text', ''), node.get('bounds')) for node in self.nodes()
                if node.get('text') or node.get('id')]

    def clickable_bounds(self, node, nav=False):
        bounds = node.get('bounds')
        if not isinstance(bounds, list) or len(bounds) != 4:
            return False
        left, top, right, bottom = bounds
        low, high = (0, self.args.height) if nav else (self.safe_top, self.safe_bottom)
        return 0 <= left < right <= self.args.width and low <= top < bottom <= high

    def seek(self, predicate, description, nav=False):
        for direction in ['up', 'down']:
            previous = None
            stable = 0
            for _ in range(18):
                found = next((node for node in self.nodes() if predicate(node) and self.clickable_bounds(node, nav)), None)
                if found:
                    return found
                current = self.signature()
                stable = stable + 1 if current == previous else 0
                if stable >= 2:
                    break
                previous = current
                self.swipe(direction)
        raise RuntimeError('Visible control not found after main-Scroll reached stable boundaries: ' + description)

    def tap_id(self, key):
        self.tap(self.seek(lambda node: node.get('id') == key, key, nav=key.startswith('nav-tab-')))

    def tap_text(self, text):
        self.tap(self.seek(lambda node: node.get('text') == text, text))

    def is_named_card(self, node, prefix, name):
        return str(node.get('id', '')).startswith(prefix) and any(child.get('text') == name for child in flatten(node))

    def tap_record(self, prefix, name):
        self.tap(self.seek(lambda node: self.is_named_card(node, prefix, name), 'exact QA record card ' + name))

    def record_visible(self, prefix, name):
        return any(self.is_named_card(node, prefix, name) for node in self.nodes())

    def expect_id(self, key, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            found = self.find_id(key)
            if found:
                return found
            time.sleep(.2)
        raise AssertionError('Expected UI state missing: ' + key)

    def expect_text(self, text):
        return self.seek(lambda node: node.get('text') == text, text)

    def set_input(self, key, value):
        self.tap_id(key)
        self.key(2072, 2017)  # UITest Ctrl+A, as used by the existing page-check script.
        self.cmd('ui', 'text', value)
        time.sleep(.2)
        # A keyboard was explicitly opened by the tap above. This Back dismisses that keyboard only.
        self.key('Back')
        if self.find_text('放弃未保存的修改？') or self.find_text('放弃这次填写？'):
            # Some keyboard builds hide themselves after ui text. Preserve the current edit in that case.
            self.tap_text('继续编辑')
        self.seek(lambda node: node.get('id') == key, key)

    def ensure_main(self):
        if not self.find_id('nav-tab-0'):
            raise RuntimeError('Start LumiKit at its main tabs; refusing to dismiss an unknown page or unsaved user edit')

    def open_tool(self, key):
        self.ensure_main()
        self.tap_id('nav-tab-1')
        self.set_input('tool-search', key)
        self.tap_id('tool-' + key)

    def back_to_main(self, max_back=5):
        for _ in range(max_back):
            if self.find_id('nav-tab-0'):
                return
            self.key('Back')
            if self.find_text('放弃未保存的修改？') or self.find_text('放弃这次填写？'):
                raise RuntimeError('Unexpected unsaved-edit confirmation; stopping instead of discarding data')
        raise AssertionError('Did not return to main tabs within known QA page depth')

    def screenshot(self, label):
        path = self.out / (label + '.png')
        if path.exists():
            path.unlink()
        self.cmd('ui', 'screenshot', '--path', path)
        return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)

    @contextmanager
    def step(self, label):
        entry = {'index': len(self.report['steps']) + 1, 'name': label, 'status': 'running'}
        self.report['steps'].append(entry)
        self.flush()
        started = time.monotonic()
        try:
            yield entry
            entry['status'] = 'pass'
        except Exception as error:
            entry['status'] = 'fail'
            entry['error'] = str(error)
            self.report['findings'].append({'step': label, 'message': str(error)})
            raise
        finally:
            entry['elapsedSeconds'] = round(time.monotonic() - started, 2)
            stem = f"{entry['index']:02d}-{re.sub('[^a-zA-Z0-9_-]', '-', label)}"
            try:
                entry['screenshot'] = self.screenshot(stem)
                tree = self.layout()
                (self.out / (stem + '.json')).write_text(json.dumps(tree, ensure_ascii=False, indent=2))
                entry['visibleTexts'] = [node.get('text') for node in flatten(tree) if node.get('text')]
            except Exception as error:
                entry['evidenceError'] = str(error)
            self.flush()
            print(json.dumps(entry, ensure_ascii=False), flush=True)

    def inventory(self):
        with self.step('inventory-open-and-empty-validation'):
            self.open_tool('inventory')
            self.expect_id('inventory-page-list')
            self.tap_id('inventory-create')
            self.tap_id('inventory-save')
            self.expect_text('请填写物品名称')
        with self.step('inventory-create-real-record'):
            values = {'物品名称 *': self.item_name, '分类': 'QA Validation', '品牌': 'QA Brand',
                      '型号': 'QA-001', '购买价格 / 元': '299.50', '购买日期': '2026-01-01',
                      '保修截止日期': (datetime.now(ZoneInfo('Asia/Shanghai')).date() + timedelta(days=7)).isoformat(),
                      '购买渠道': 'QA Local'}
            for label, value in values.items():
                self.set_input('inventory-input-' + label, value)
            self.set_input('inventory-notes', 'Created only by LumiKit automated QA')
            self.tap_id('inventory-save')
            self.expect_id('inventory-page-detail')
            self.expect_text(self.item_name)
            self.report['created'].append({'kind': 'inventory', 'name': self.item_name})
        with self.step('inventory-edit-and-read-back'):
            self.tap_id('inventory-edit')
            self.set_input('inventory-input-物品名称 *', self.edited_name)
            self.set_input('inventory-input-型号', 'QA-002')
            self.tap_id('inventory-save')
            self.expect_id('inventory-page-detail')
            self.expect_text(self.edited_name)
            self.expect_text('QA Brand QA-002')
            self.report['created'][-1]['name'] = self.edited_name
        with self.step('inventory-persistence-search'):
            self.restart_app()
            self.open_tool('inventory')
            self.set_input('inventory-search', self.edited_name)
            self.tap_record('inventory-card-', self.edited_name)
            self.expect_id('inventory-page-detail')
            self.expect_text('QA Brand QA-002')
        with self.step('inventory-lend'):
            self.set_input('inventory-borrower', 'QA Borrower')
            self.tap_id('inventory-lend')
            self.expect_id('inventory-return')
        with self.step('inventory-return'):
            self.tap_id('inventory-return')
            self.expect_id('inventory-lend')
            self.seek(lambda node: 'QA Borrower' in node.get('text', '') and '归还' in node.get('text', ''), 'saved return history')
        with self.step('inventory-archive-and-filter'):
            self.tap_id('inventory-archive')
            self.expect_text('恢复在用')
            self.key('Back')
            self.expect_id('inventory-page-list')
            self.tap_id('inventory-filter-已归档')
            self.set_input('inventory-search', self.edited_name)
            self.tap_record('inventory-card-', self.edited_name)
            self.expect_id('inventory-page-detail')
            self.expect_text('恢复在用')
        with self.step('inventory-delete-only-own-record'):
            actual = self.seek(lambda node: node.get('id') == 'inventory-detail-name', 'QA detail name').get('text')
            if actual != self.edited_name or not actual.startswith('QA-LumiKit-' + self.run_id):
                raise AssertionError('Refusing deletion: current inventory item is not this run\'s QA record')
            self.tap_id('inventory-delete')
            self.expect_text('删除后无法恢复该物品档案和借出记录。')
            self.tap_text('删除')
            self.expect_id('inventory-page-list')
            self.set_input('inventory-search', self.edited_name)
            if self.record_visible('inventory-card-', self.edited_name):
                raise AssertionError('Deleted QA inventory record still appears')
            self.report['deleted'].append({'kind': 'inventory', 'name': self.edited_name})
            self.back_to_main()

    def add_field(self, label, kind, required=False, options=None):
        self.tap_id('forms-add-field')
        self.expect_id('forms-page-field')
        self.set_input('forms-input-字段名称 *', label)
        self.tap_id('forms-type-' + kind)
        if required:
            self.tap_id('forms-field-required')
        if options:
            self.set_input('forms-field-options', '\n'.join(options))
        self.tap_id('forms-field-save')
        self.expect_id('forms-page-edit')

    def export_pdf_and_cancel_picker(self, button_id):
        self.tap_id(button_id)
        deadline = time.monotonic() + 15
        picker = False
        while time.monotonic() < deadline:
            controls = self.nodes()
            own_button = any(node.get('id') == button_id for node in controls)
            text = '\n'.join(str(node.get('text', '')) for node in controls)
            if not own_button and any(label in text for label in ['保存', '位置', '另存为', '选择文件夹']):
                picker = True
                break
            time.sleep(.3)
        if not picker:
            raise AssertionError('PDF export did not reach the system save picker; check font/PDF errors in screenshot')
        self.report['steps'][-1]['pickerScreenshot'] = self.screenshot(f'picker-{button_id}')
        self.key('Back')
        self.expect_id(button_id)
        # The actual output is verified later through FileService's real workspace list and PDF preview.

    def forms(self):
        with self.step('forms-create-schema'):
            self.open_tool('forms')
            self.tap_id('forms-create')
            self.set_input('forms-input-表单标题 *', self.form_name)
        with self.step('forms-add-required-text'):
            self.add_field('QAName', 'text', required=True)
        with self.step('forms-add-number'):
            self.add_field('QACount', 'number')
        with self.step('forms-add-radio-options'):
            self.add_field('QAChoice', 'radio', options=['Alpha', 'Beta'])
        with self.step('forms-save-schema'):
            self.tap_id('forms-save-schema')
            self.expect_id('forms-delete')
            self.report['created'].append({'kind': 'form', 'name': self.form_name})
        with self.step('forms-export-blank-pdf'):
            self.export_pdf_and_cancel_picker('forms-export-template-pdf')
        with self.step('forms-required-validation'):
            self.tap_id('forms-fill')
            self.expect_id('forms-page-fill')
            self.tap_id('forms-submit')
            message = self.seek(lambda node: node.get('id') == 'forms-validation-message', 'required validation').get('text', '')
            if 'QAName' not in message or '请填写' not in message:
                raise AssertionError('Required text field did not prevent an empty submission: ' + message)
        with self.step('forms-fill-and-save-response'):
            self.set_input('forms-answer-QAName', 'QA Alice')
            self.set_input('forms-answer-QACount', '42')
            self.tap_id('forms-choice-QAChoice-Alpha')
            self.tap_id('forms-submit')
            self.expect_id('forms-page-responses')
            self.expect_text('1 份本地回答')
        with self.step('forms-open-saved-response'):
            self.open_and_check_saved_response()
        with self.step('forms-answer-persists-after-process-restart'):
            self.restart_app()
            self.open_tool('forms')
            self.set_input('forms-search', self.form_name)
            self.tap_record('forms-card-', self.form_name)
            self.expect_id('forms-page-edit')
            self.tap_id('forms-responses')
            self.expect_id('forms-page-responses')
            self.expect_text('1 份本地回答')
            self.open_and_check_saved_response()
        with self.step('forms-export-response-pdf'):
            self.export_pdf_and_cancel_picker('forms-export-response-pdf')
        with self.step('forms-delete-only-own-schema-and-answers'):
            self.key('Back')
            self.expect_id('forms-page-responses')
            self.key('Back')
            self.expect_id('forms-page-edit')
            node = self.seek(lambda node: node.get('id') == 'forms-input-表单标题 *', 'QA form title')
            if node.get('text') != self.form_name:
                raise AssertionError('Refusing deletion: selected form is not this run\'s QA schema')
            self.tap_id('forms-delete')
            self.expect_text('表单定义及其本地回答将一起删除，此操作无法撤销。')
            self.tap_text('删除')
            self.expect_id('forms-page-list')
            self.set_input('forms-search', self.form_name)
            if self.record_visible('forms-card-', self.form_name):
                raise AssertionError('Deleted QA schema remains in the filtered list')
            self.report['deleted'].append({'kind': 'form', 'name': self.form_name})
            self.back_to_main()
        self.check_pdf_workspace()

    def open_and_check_saved_response(self):
        self.tap(self.seek(lambda node: str(node.get('id', '')).startswith('forms-response-card-'), 'QA response card'))
        self.expect_id('forms-page-response')
        self.expect_text(self.form_name)
        for label, value in [('QAName', 'QA Alice'), ('QACount', '42'), ('QAChoice', 'Alpha')]:
            node = self.seek(lambda node: node.get('id') == 'forms-value-' + label, label)
            if node.get('text') != value:
                raise AssertionError(f'Saved answer {label} differs: {node.get("text")}')

    def workspace_row(self, filename):
        self.seek(lambda node: node.get('text') == filename, filename)
        candidates = []
        for node in self.nodes():
            descendants = flatten(node)
            texts = [child.get('text') for child in descendants]
            if filename in texts and '移除副本' in texts and '预览' in texts:
                candidates.append((len(descendants), node))
        if not candidates:
            raise AssertionError('Could not isolate the exact QA workspace row: ' + filename)
        return min(candidates, key=lambda pair: pair[0])[1]

    def row_action(self, filename, action):
        self.workspace_row(filename)
        for _ in range(8):
            candidates = []
            for node in self.nodes():
                descendants = flatten(node)
                texts = [child.get('text') for child in descendants]
                if filename in texts and action in texts:
                    candidates.append((len(descendants), node))
            if not candidates:
                self.workspace_row(filename)
                continue
            row = min(candidates, key=lambda pair: pair[0])[1]
            target = next((node for node in flatten(row) if node.get('text') == action), None)
            if target and self.clickable_bounds(target):
                self.tap(target)
                return
            bounds = target.get('bounds', []) if target else []
            self.swipe('down' if bounds and bounds[1] < self.safe_top else 'up')
        raise AssertionError('Action not safely visible in exact QA file row: ' + action)

    def check_pdf_workspace(self):
        with self.step('forms-open-real-generated-pdf-workspace'):
            self.ensure_main()
            self.tap_id('nav-tab-3')
            self.tap_text('文件工作区')
            self.expect_text('你的文件，集中有序')
        for index, filename in enumerate(self.pdf_names):
            with self.step(f'forms-pdf-{index + 1}-exists-and-previews') as entry:
                row = self.workspace_row(filename)
                sizes = [node.get('text', '') for node in flatten(row) if re.fullmatch(r'[0-9.]+\s*[KMG]?B', node.get('text', ''))]
                if not sizes or not any(float(re.match(r'[0-9.]+', size).group()) > 0 for size in sizes):
                    raise AssertionError('QA PDF is not listed as a nonempty real workspace file: ' + filename)
                entry['filename'] = filename
                entry['sizes'] = sizes
                self.row_action(filename, '预览')
                self.expect_text('文件预览')
                time.sleep(.8)
                if 'PDF 预览失败' in self.alltext():
                    raise AssertionError('Generated QA PDF could not be previewed')
                entry['previewScreenshot'] = self.screenshot(f'qa-pdf-{index + 1}-preview')
                (self.out / f'qa-pdf-{index + 1}-preview.json').write_text(json.dumps(self.layout(), ensure_ascii=False, indent=2))
                self.report['pdfEvidence'].append({'name': filename, 'nonzeroWorkspaceSize': sizes,
                                                   'previewSectionOpened': True, 'pickerCancelled': True})
                self.tap_text('收起')
            with self.step(f'forms-pdf-{index + 1}-delete-only-own-copy'):
                if filename not in self.pdf_names or not filename.startswith('QA-LumiKit-' + self.run_id):
                    raise AssertionError('Refusing to remove a non-QA workspace file')
                self.row_action(filename, '移除副本')
                self.expect_text('移除工作区副本？')
                self.tap_text('移除')
                if self.find_text(filename):
                    raise AssertionError('QA workspace PDF was not removed')
                self.report['deleted'].append({'kind': 'workspace', 'name': filename})
        self.back_to_main()

    def run(self):
        try:
            with self.step('precondition-main-tabs'):
                self.ensure_main()
            if self.args.only in ['all', 'inventory']:
                self.inventory()
            if self.args.only in ['all', 'forms']:
                self.forms()
            self.report['status'] = 'pass'
        except Exception as error:
            self.report['status'] = 'fail'
            self.report['error'] = str(error)
            # No blind cleanup/navigation after a failure: retained names allow precise manual recovery.
            self.report['remainingQaRecords'] = [entry for entry in self.report['created'] if entry not in self.report['deleted']]
            print('STOPPED:', error, file=sys.stderr, flush=True)
        finally:
            self.report['finishedAt'] = datetime.now().astimezone().isoformat()
            self.flush()
        return 0 if self.report['status'] == 'pass' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='127.0.0.1:5555')
    parser.add_argument('--only', choices=['all', 'inventory', 'forms'], default='all')
    parser.add_argument('--output', default='docs/screenshots/emulator/business')
    parser.add_argument('--width', type=int, default=1320, help='Actual screenshot width in pixels')
    parser.add_argument('--height', type=int, default=2848, help='Actual screenshot height in pixels')
    args = parser.parse_args()
    return BusinessCheck(args).run()


if __name__ == '__main__':
    sys.exit(main())
