#!/usr/bin/env python3
"""Exercise Analytics through DevEco CLI UI; start after emulator-check.py returned to Tools.

Does not build, install, launch, read app-private data, or auto-save outside the app.
Exports open the real system picker and are cancelled. Only this run's unique QA
project may be deleted. Existing saved projects are inventoried and preserved.
This script has intentionally not been executed as part of its creation.
"""
import argparse
import datetime
import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NODE = os.environ.get('LUMI_NODE_BIN', '/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node')
CLI = os.environ.get('LUMI_DEVECO_CLI', '/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js')
HDC = os.environ.get('LUMI_HDC', '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc')
# ASCII fixture avoids the observed CLI text-injection issue with Chinese input.
# The separate built-in-sample check still covers the app's native Chinese data.
QA_CSV = ('Faculty,Month,Amount\nDesign,Jan,128\nComputing,Jan,256\nDesign,Feb,198\n'
          'Business,Feb,180\nComputing,Mar,320\nBusiness,Mar,220\nDesign,Mar,160\n'
          'Design,Jan,128\n,Apr,\n,,')


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='127.0.0.1:5555')
    parser.add_argument('--output', default='docs/screenshots/emulator/analytics')
    return parser.parse_args()


class AnalyticsCheck:
    def __init__(self, args):
        self.device = args.device
        self.run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        self.qa_name = 'QA_Analytics_' + self.run_id
        self.out = (ROOT / args.output / self.run_id).resolve()
        self.out.mkdir(parents=True, exist_ok=False)
        self.results = []
        self.baseline = {}
        self.created_project_id = None
        self.save_attempted = False
        self.scroll_bounds = None

    def cmd(self, *parts, timeout=25):
        result = subprocess.run([NODE, CLI, *parts, '--device', self.device], cwd=ROOT,
                                text=True, capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError((result.stdout + result.stderr)[-2000:])
        return result.stdout

    def layout(self):
        return json.loads(self.cmd('ui', 'layout', '--format', 'json'))

    @staticmethod
    def flatten(data):
        if isinstance(data, list):
            return [node for child in data for node in AnalyticsCheck.flatten(child)]
        if not isinstance(data, dict):
            return []
        return [data] + [node for child in data.get('children', []) for node in AnalyticsCheck.flatten(child)]

    def nodes(self):
        return self.flatten(self.layout())

    @staticmethod
    def bounds(node):
        rect = node.get('bounds', [])
        if not isinstance(rect, list) or len(rect) != 4:
            raise RuntimeError('UI node has no usable rectangle: ' + str(node.get('id')))
        return [int(value) for value in rect]

    @staticmethod
    def visible(node):
        rect = node.get('bounds', [])
        return node.get('visible', True) is not False and isinstance(rect, list) and len(rect) == 4 and rect[2] > rect[0] and rect[3] > rect[1]

    def node(self, key, data=None):
        return next((node for node in (data if data is not None else self.nodes())
                     if node.get('id') == key and self.visible(node)), None)

    def center_is_visible(self, node, allow_chrome=False):
        rect = self.bounds(node)
        x, y = (rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2
        right = self.scroll_bounds[2] if self.scroll_bounds else 1320
        bottom = self.scroll_bounds[3] if self.scroll_bounds else 2848
        # layout may include off-screen nodes. The observed 1320x2848 phone
        # content-safe center range is y=320..2650; scale with its viewport.
        y_min = 0 if allow_chrome else round(bottom * 320 / 2848)
        y_max = bottom if allow_chrome else round(bottom * 2650 / 2848)
        return 0 <= x < right and y_min <= y <= y_max

    def click(self, node, allow_chrome=False):
        if not self.center_is_visible(node, allow_chrome):
            key = node.get('id')
            if key and not allow_chrome:
                node = self.seek(key)
            else:
                raise RuntimeError('Refusing to tap an off-screen node: ' + str(key))
        if not self.center_is_visible(node, allow_chrome):
            raise RuntimeError('Control center is outside the safe viewport')
        rect = self.bounds(node)
        self.cmd('ui', 'click', str((rect[0] + rect[2]) // 2), str((rect[1] + rect[3]) // 2))
        time.sleep(.3)

    def back(self):
        subprocess.run([HDC, '-t', self.device, 'shell', 'uitest uiInput keyEvent Back'],
                       text=True, capture_output=True, check=True, timeout=10)
        time.sleep(.4)

    def screenshot(self, name):
        target = self.out / (name + '.png')
        self.cmd('ui', 'screenshot', '--path', str(target))
        return str(target)

    def remember_viewport(self):
        data = self.nodes()
        scroll = self.node('analytics-scroll', data)
        if scroll:
            self.scroll_bounds = self.bounds(scroll)
        elif not self.scroll_bounds:
            rects = [self.bounds(node) for node in data if self.visible(node)]
            if not rects:
                raise RuntimeError('Cannot determine visible viewport')
            self.scroll_bounds = [min(r[0] for r in rects), min(r[1] for r in rects),
                                  max(r[2] for r in rects), max(r[3] for r in rects)]

    def swipe_page(self, direction):
        self.remember_viewport()
        left, top, right, bottom = self.scroll_bounds
        # Right margin avoids nested TextArea/table scroll interception. At 1320x2848
        # this is close to the manually observed x=1300,y=2400..550 gesture.
        width, height = right - left, bottom - top
        x = right - max(12, int(width * .015))
        y_top = top + max(180, int(height * .20))
        y_bottom = bottom - max(120, int(height * .15))
        if y_bottom <= y_top:
            raise RuntimeError('Scroll viewport is too small')
        start, end = (y_bottom, y_top) if direction == 'up' else (y_top, y_bottom)
        self.cmd('ui', 'swipe', str(x), str(start), str(x), str(end), '--speed', '2000')
        time.sleep(.2)

    @staticmethod
    def fingerprint(data):
        return [(node.get('id', ''), node.get('text', ''), node.get('bounds'))
                for node in data if node.get('text') or str(node.get('id', '')).startswith('analytics-')]

    def scroll_edge(self, direction):
        previous = None
        stable = 0
        for _ in range(20):
            self.swipe_page(direction)
            current = self.fingerprint(self.nodes())
            stable = stable + 1 if current == previous else 0
            if stable >= 2:
                return
            previous = current
        raise RuntimeError('Could not confirm scroll edge: ' + direction)

    def seek(self, key):
        found = self.node(key)
        if found and self.center_is_visible(found):
            return found
        self.scroll_edge('down')
        previous = None
        for _ in range(22):
            data = self.nodes()
            found = self.node(key, data)
            if found and self.center_is_visible(found):
                return found
            current = self.fingerprint(data)
            if current == previous:
                break
            previous = current
            self.swipe_page('up')
        raise RuntimeError('Visible control not found: ' + key)

    def tap_id(self, key):
        self.click(self.seek(key))

    def wait_for(self, predicate, description, timeout=12):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            data = self.nodes()
            if predicate(data):
                return data
            time.sleep(.2)
        raise AssertionError('Timed out: ' + description)

    def replace_text(self, key, value):
        self.click(self.seek(key))
        subprocess.run([HDC, '-t', self.device, 'shell', 'uitest uiInput keyEvent 2072 2017'],
                       text=True, capture_output=True, check=True, timeout=10)
        self.cmd('ui', 'text', value)
        self.back()  # Dismiss the keyboard, as in emulator-check.py.
        self.wait_for(lambda data: self.node('analytics-scroll', data) is not None,
                      'Analytics remains visible after text entry')

    def text(self, key):
        node = self.seek(key)
        direct = node.get('text', '')
        return direct or '\n'.join(child.get('text', '') for child in self.flatten(node) if child.get('text'))

    def expect_text(self, key, expected):
        actual = self.text(key)
        assert actual == expected, f'{key}: expected {expected!r}, got {actual!r}'

    def expect_message(self, part):
        actual = self.text('analytics-message')
        assert part in actual, f'Expected message {part!r}, got {actual!r}'

    def choose(self, key, value):
        anchor = self.seek(key)
        rect = self.bounds(anchor)
        self.click(anchor)
        candidates = [node for node in self.nodes() if node.get('text') == value and self.visible(node) and self.center_is_visible(node)]
        # Ignore the Select's current label and named table/stat nodes. The menu
        # may open above or below the anchor depending on available space.
        choices = []
        for node in candidates:
            bounds = self.bounds(node)
            x, y = (bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2
            if rect[0] <= x <= rect[2] and rect[1] <= y <= rect[3]:
                continue
            if str(node.get('id', '')).startswith('analytics-'):
                continue
            choices.append(node)
        if not choices:
            self.back()
            raise RuntimeError('Select option not found: ' + value)
        choices.sort(key=lambda node: 0 if 'MenuItem' in str(node.get('type', '')) else 1)
        self.click(choices[0])
        actual = self.text(key)
        assert value in actual, f'Select did not change to {value}: {actual!r}'

    def record(self, name, run):
        entry = {'check': name}
        try:
            detail = run()
            entry.update({'status': 'pass', 'detail': detail})
        except Exception as error:
            entry.update({'status': 'fail', 'error': str(error)})
            try:
                entry['screenshot'] = self.screenshot('failure-' + str(len(self.results)))
            except Exception:
                pass
            self.results.append(entry)
            print(json.dumps(entry, ensure_ascii=False), flush=True)
            raise
        self.results.append(entry)
        print(json.dumps(entry, ensure_ascii=False), flush=True)

    def open_analytics(self):
        # Preconditions intentionally match emulator-check.py: the app is running
        # and the preceding 22-tool check left it on the Tools page.
        self.cmd('ui', 'click', '--id', 'nav-tab-1')
        self.cmd('ui', 'click', '--id', 'tool-search')
        subprocess.run([HDC, '-t', self.device, 'shell', 'uitest uiInput keyEvent 2072 2017'],
                       text=True, capture_output=True, check=True, timeout=10)
        self.cmd('ui', 'text', 'analytics')
        self.back()
        self.cmd('ui', 'click', '--id', 'tool-analytics')
        self.wait_for(lambda data: self.node('analytics-scroll', data) is not None, 'Analytics route opened')
        self.remember_viewport()
        title = self.node('HdsTitleBar')
        assert title is not None, 'HDS title bar missing'
        assert self.bounds(title)[1] >= 100, 'Title overlaps status area'
        return {'screenshot': self.screenshot('analytics-top'), 'titleBounds': self.bounds(title)}

    def project_rows(self):
        result = {}
        self.scroll_edge('down')
        previous = None
        for _ in range(24):
            data = self.nodes()
            for node in data:
                key = str(node.get('id', ''))
                if key.startswith('analytics-project-name-') and key != 'analytics-project-name-input':
                    result[key.removeprefix('analytics-project-name-')] = node.get('text', '')
            current = self.fingerprint(data)
            if current == previous:
                break
            previous = current
            self.swipe_page('up')
        return result

    def sample_check(self):
        self.tap_id('analytics-sample')
        self.scroll_edge('down')
        self.wait_for(lambda data: any('已解析 7 行、3 列' in node.get('text', '') for node in data), 'built-in CSV sample parsed')
        self.expect_text('analytics-stat-value-数据行', '7')
        self.expect_text('analytics-stat-value-字段', '3')
        self.expect_text('analytics-stat-value-求和', '1462')
        self.expect_text('analytics-stat-value-平均值', '208.86')
        return 'Built-in seven-row sample parsed; sum 1462 and mean 208.86 verified.'

    def load_qa_data(self):
        self.tap_id('analytics-input-toggle')
        self.replace_text('analytics-input', QA_CSV)
        self.tap_id('analytics-parse')
        self.scroll_edge('down')
        self.wait_for(lambda data: any('已解析 10 行、3 列' in node.get('text', '') for node in data), 'QA CSV parsed')
        self.expect_text('analytics-stat-value-数据行', '10')
        self.expect_text('analytics-stat-value-空单元格', '5')
        self.expect_text('analytics-cell-0-0', 'Design')
        self.expect_text('analytics-cell-0-2', '128')
        self.expect_text('analytics-cell-7-0', 'Design')
        self.expect_text('analytics-cell-7-2', '128')
        self.replace_text('analytics-project-name-input', self.qa_name)
        return 'Ten QA rows include one repeated row, one partially empty row, and one all-empty row.'

    def cleaning_check(self):
        self.replace_text('analytics-filter-input', 'Design')
        self.tap_id('analytics-filter-apply')
        self.expect_message('当前 4 行')
        self.tap_id('analytics-restore')
        self.choose('analytics-field-select', 'Amount')
        self.tap_id('analytics-sort-desc')
        self.expect_message('已降序排列')
        self.expect_text('analytics-cell-0-2', '320')
        self.tap_id('analytics-sort-asc')
        self.expect_message('已升序排列')
        self.expect_text('analytics-cell-0-2', '128')
        self.tap_id('analytics-restore')
        self.choose('analytics-field-select', 'Faculty')
        self.tap_id('analytics-null-only')
        self.expect_message('当前 2 行')
        self.tap_id('analytics-restore')
        self.tap_id('analytics-remove-blank')
        self.expect_message('当前 9 行')
        self.tap_id('analytics-restore')
        self.tap_id('analytics-deduplicate')
        self.expect_message('已移除 1 条整行重复记录')
        self.tap_id('analytics-restore')
        # Persist the cleaned version: original seven rows + the partially empty row.
        self.tap_id('analytics-deduplicate')
        self.tap_id('analytics-remove-blank')
        self.expect_message('当前 8 行')
        return {'rowsAfterCleaning': 8, 'screenshot': self.screenshot('analytics-cleaning')}

    def stats_check(self):
        self.expect_text('analytics-stat-value-求和', '1462')
        self.expect_text('analytics-stat-value-平均值', '208.86')
        self.expect_text('analytics-stat-value-最小值', '128')
        self.expect_text('analytics-stat-value-最大值', '320')
        self.expect_text('analytics-stats-summary', '有效数值 7  ·  空值 1  ·  非数值 0')
        self.expect_text('analytics-group-summary', '按「Faculty」分组，共 4 组')
        for label, value in [('Design', '3 条 · 486'), ('Computing', '2 条 · 576'), ('Business', '2 条 · 400'), ('', '1 条 · 0')]:
            self.expect_text('analytics-group-value-' + label, value)
        return {'sum': 1462, 'mean': 208.86, 'min': 128, 'max': 320, 'groups': 4,
                'screenshot': self.screenshot('analytics-statistics')}

    def charts_check(self):
        images = []
        self.choose('analytics-chart-metric', '数值合计')
        for index, label in enumerate(['条形图', '柱状图', '折线图', '饼图']):
            self.choose('analytics-chart-type', label)
            chart = self.seek('analytics-chart')
            rect = self.bounds(chart)
            assert rect[2] > rect[0] and rect[3] > rect[1], 'Canvas has no visible area'
            images.append({'type': label, 'screenshot': self.screenshot('analytics-chart-' + str(index))})
        return {'checks': 'Native Select state and visible Canvas checked; screenshots retained for visual review.', 'charts': images}

    def cancel_export(self, key, suffix):
        self.tap_id(key)
        data = self.wait_for(lambda nodes: self.node('analytics-scroll', nodes) is None and
                             any(self.qa_name in node.get('text', '') or node.get('text') in ['保存', '另存为', '取消', '文件名'] for node in nodes),
                             'real system save picker for ' + suffix)
        picker_shot = self.screenshot('analytics-picker-' + suffix)
        (self.out / ('picker-' + suffix + '-layout.json')).write_text(json.dumps(data, ensure_ascii=False, indent=2))
        cancel = next((node for node in data if node.get('text') in ['取消', 'Cancel'] and self.visible(node)), None)
        if cancel:
            self.click(cancel, allow_chrome=True)
        else:
            self.back()
        self.wait_for(lambda nodes: self.node('analytics-scroll', nodes) is not None, 'Analytics returned after picker cancellation')
        message = self.text('analytics-message')
        assert not message.startswith('已导出 ' + self.qa_name), 'Cancelled picker was reported as a successful export'
        return {'pickerScreenshot': picker_shot, 'messageAfterCancel': message,
                'note': 'The app retains its own QA output copy in the workspace; no external file was saved.'}

    def save_open_delete(self):
        if len(self.baseline) >= 10:
            raise RuntimeError('Already 10 saved projects: refusing to save QA data because the app would evict an existing project.')
        self.replace_text('analytics-project-name-input', self.qa_name)
        self.save_attempted = True
        self.tap_id('analytics-save-project')
        self.expect_message('已保存分析项目')
        projects = self.project_rows()
        matches = [key for key, name in projects.items() if name == self.qa_name]
        assert len(matches) == 1, 'The unique QA project was not found exactly once'
        self.created_project_id = matches[0]
        assert all(projects.get(key) == name for key, name in self.baseline.items()), 'A pre-existing project changed during QA save'
        # Alter the in-memory view, then reopen the saved eight-row project.
        self.replace_text('analytics-filter-input', 'Design')
        self.tap_id('analytics-filter-apply')
        self.expect_message('当前 3 行')
        self.tap_id('analytics-project-open-' + self.created_project_id)
        self.scroll_edge('down')
        self.wait_for(lambda nodes: any('已解析 8 行、3 列' in node.get('text', '') for node in nodes), 'saved QA project reopened')
        self.expect_text('analytics-stat-value-数据行', '8')
        opened = self.screenshot('analytics-project-reopened')
        self.delete_own_project()
        after = self.project_rows()
        assert after == self.baseline, 'Saved projects do not match the pre-test inventory after QA cleanup'
        return {'qaProject': self.qa_name, 'reopenedScreenshot': opened, 'preservedProjects': len(self.baseline)}

    def delete_own_project(self):
        if not self.save_attempted:
            return
        projects = self.project_rows()
        matches = [key for key, name in projects.items() if name == self.qa_name]
        if not matches:
            return
        assert len(matches) == 1, 'Refusing ambiguous QA project cleanup'
        project_id = matches[0]
        if self.created_project_id:
            assert project_id == self.created_project_id, 'Refusing to delete a different project'
        self.tap_id('analytics-project-delete-' + project_id)
        time.sleep(.4)
        assert self.qa_name not in self.project_rows().values(), 'QA project deletion did not persist in the visible list'
        self.created_project_id = None
        self.save_attempted = False

    def run(self):
        success = False
        try:
            self.record('open-and-safe-title', self.open_analytics)
            self.baseline = self.project_rows()
            self.record('builtin-csv-sample', self.sample_check)
            self.record('qa-csv-with-duplicates-and-empty-cells', self.load_qa_data)
            self.record('filter-sort-empty-rows-deduplicate', self.cleaning_check)
            self.record('numeric-statistics-and-groups', self.stats_check)
            self.record('four-native-chart-modes', self.charts_check)
            self.record('csv-system-picker-cancel', lambda: self.cancel_export('analytics-export-csv', 'csv'))
            self.record('json-system-picker-cancel', lambda: self.cancel_export('analytics-export-json', 'json'))
            self.record('group-summary-system-picker-cancel', lambda: self.cancel_export('analytics-export-groups', 'groups-csv'))
            self.record('save-reopen-delete-only-own-qa-project', self.save_open_delete)
            self.scroll_edge('up')
            assert self.node('analytics-save-project') or any(str(node.get('id', '')).startswith('analytics-project-') for node in self.nodes()), 'Expected final controls missing at confirmed bottom'
            self.results.append({'check': 'confirmed-bottom', 'status': 'pass', 'screenshot': self.screenshot('analytics-bottom')})
            self.scroll_edge('down')
            self.results.append({'check': 'confirmed-top', 'status': 'pass', 'screenshot': self.screenshot('analytics-top-final')})
            success = True
        finally:
            try:
                if self.save_attempted:
                    self.delete_own_project()
            except Exception as error:
                self.results.append({'check': 'cleanup-own-qa-project', 'status': 'fail', 'error': str(error), 'qaProject': self.qa_name})
                success = False
            report = {'device': self.device, 'qaProject': self.qa_name, 'runId': self.run_id,
                      'status': 'pass' if success else 'fail', 'results': self.results,
                      'retainedWorkspaceArtifacts': [self.qa_name + '_清洗结果.csv', self.qa_name + '_清洗结果.json', self.qa_name + '_分组汇总.csv']}
            (self.out / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
            print(json.dumps({'status': report['status'], 'report': str(self.out / 'results.json')}, ensure_ascii=False), flush=True)
            try:
                if self.node('analytics-scroll'):
                    self.back()  # Restore the preceding script's Tools-page postcondition.
            except Exception:
                pass
        return success


def main():
    check = AnalyticsCheck(parse_args())
    try:
        return 0 if check.run() else 1
    except Exception as error:
        print('Analytics verification failed:', error, flush=True)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
