#!/usr/bin/env python3
"""Check a known QA file through LumiKit workspace, cross-tool results and native panels.

Run alone with LumiKit already at its main tabs. Provide an exact --filename already present in
the workspace, or --qa-report from the business check. No file or business record is deleted.
PDF -> extracted PDF; CSV -> JSON; JSON -> CSV; TXT/MD -> Markdown; image -> JPEG -> A4 PDF.
Native save/share panels are captured and cancelled. Unknown panel layouts stop the check rather
than pretending that tapping a button proves success. Optional marker arguments accept a visible
text verified from the actual system panel. This script never accesses application databases.
"""
import argparse
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('lumikit_business_check', ROOT / 'scripts/emulator-business-check.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
BusinessCheck = module.BusinessCheck
flatten = module.flatten


def report_filename(path):
    data = json.loads(Path(path).read_text())
    removed = {entry.get('name') for entry in data.get('deleted', []) if entry.get('kind') == 'workspace'}
    names = [entry.get('name', '') for entry in data.get('pdfEvidence', [])]
    names += [entry.get('name', '') for entry in data.get('created', []) if entry.get('kind') == 'workspace']
    names = [name for name in names if name.startswith('QA-LumiKit-') and name not in removed]
    if not names:
        raise ValueError('The report has no retained QA workspace file; pass --filename for a known QA file instead')
    return names[-1]


class FileWorkflowCheck(BusinessCheck):
    def __init__(self, args):
        super().__init__(args)
        self.source_filename = args.filename or report_filename(args.qa_report)
        if Path(self.source_filename).name != self.source_filename or not self.source_filename.strip():
            raise ValueError('Use one exact workspace basename, without directory components')
        self.stem = 'QA-LumiKit-Workflow-' + self.run_id
        self.generated = []
        self.report['sourceFilename'] = self.source_filename
        self.report['notes'] = ['Only the exact authorized source filename and this run\'s generated names are used.',
                                'No workspace file, history, business record or exported file is deleted.',
                                'Save/share are cancelled; generated private workspace results remain for review.']
        self.flush()

    def flush(self):
        (self.out / 'file-workflow-results.json').write_text(json.dumps(self.report, ensure_ascii=False, indent=2))

    def edge(self, direction):
        previous = None
        for _ in range(16):
            self.swipe(direction)
            current = self.signature()
            if current == previous:
                return
            previous = current

    def exact_row(self, filename, workspace=False):
        self.seek(lambda node: node.get('text') == filename, filename)
        candidates = []
        for node in self.nodes():
            descendants = flatten(node)
            texts = [child.get('text') for child in descendants]
            if filename in texts and '分享' in texts and '继续处理' in texts and (not workspace or '移除副本' in texts):
                candidates.append((len(descendants), node))
        if not candidates:
            raise AssertionError('Exact QA file row not found: ' + filename)
        return min(candidates, key=lambda pair: pair[0])[1]

    def file_action(self, filename, action, workspace=False):
        if filename != self.source_filename and filename not in self.generated:
            raise AssertionError('Refusing an action on a file outside this QA run: ' + filename)
        for _ in range(12):
            row = self.exact_row(filename, workspace)
            target = next((node for node in flatten(row) if node.get('text') == action), None)
            if target and self.clickable_bounds(target):
                self.tap(target)
                return
            bounds = target.get('bounds', []) if target else []
            self.swipe('down' if bounds and bounds[1] < self.safe_top else 'up')
        raise AssertionError('Exact QA row action is not safely visible: ' + filename + ' / ' + action)

    def open_workspace(self):
        self.ensure_main()
        self.tap_id('nav-tab-3')
        self.tap_text('文件工作区')
        self.expect_text('你的文件，集中有序')

    def continue_file(self, filename, action, workspace=False):
        self.file_action(filename, '继续处理', workspace)
        self.tap_text(action)
        self.expect_id('HdsTitleBar')
        # Text tools show their actual imported contents; native tools show the source filename.
        if Path(filename).suffix.lower() not in ['.csv', '.json', '.txt', '.md']:
            self.expect_text(filename)

    def name_input(self):
        candidates = []
        for node in self.nodes():
            descendants = flatten(node)
            if any(child.get('text') == '处理设置' for child in descendants):
                inputs = [child for child in descendants if child.get('type') == 'TextInput']
                if inputs:
                    candidates.append((len(descendants), inputs[0]))
        return min(candidates, key=lambda pair: pair[0])[1] if candidates else None

    def set_result_name(self, name):
        self.seek(lambda node: node.get('text') == '处理设置', '处理设置')
        target = self.name_input()
        if target is None or not self.clickable_bounds(target):
            self.edge('down')
            self.seek(lambda node: node.get('text') == '处理设置', '处理设置')
            target = self.name_input()
        if target is None:
            raise AssertionError('Result-name TextInput cannot be isolated from its settings card')
        self.tap(target)
        self.key(2072, 2017)
        self.cmd('ui', 'text', name)
        self.key('Back')

    def wait_result(self, filename, text_tool=False):
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            current = self.alltext()
            if ('转换完成，可预览或保存结果' if text_tool else '处理完成 · ') in current:
                break
            self.swipe('up')
            time.sleep(.3)
        else:
            raise AssertionError('No successful UI completion within 90 seconds; see retained screenshot')
        if text_tool:
            self.tap_text('保存结果')
            self.cancel_native_panel('save', self.args.save_panel_marker)
        self.generated.append(filename)
        self.expect_text(filename)
        row = self.exact_row(filename)
        if not any(str(node.get('text', '')).endswith((' B', ' KB', ' MB', ' GB')) for node in flatten(row)):
            # Size may be formatted without a space on some versions; exact file-row existence is still reported.
            self.report['steps'][-1]['sizeText'] = [node.get('text') for node in flatten(row) if node.get('text')]
        self.report['created'].append({'kind': 'workspace', 'name': filename})

    def cancel_native_panel(self, kind, marker=''):
        deadline = time.monotonic() + 12
        accepted = None
        known = ['保存', '保存至', '文件名', '我的手机'] if kind == 'save' else ['分享至', '分享到', '华为分享', '选择分享方式', '附近设备']
        while time.monotonic() < deadline:
            tree = self.nodes()
            texts = {str(node.get('text', '')) for node in tree if node.get('text')}
            matched = marker in texts if marker else any(word in texts for word in known)
            foreign_page = not any(node.get('id') == 'HdsTitleBar' for node in tree)
            if matched or (foreign_page and texts):
                accepted = {'kind': kind, 'matchedMarker': marker if marker and matched else
                            next((word for word in known if word in texts), ''), 'appTitleAbsent': foreign_page}
                break
            time.sleep(.3)
        if accepted is None:
            raise AssertionError(f'Cannot positively identify native {kind} panel; inspect screenshot/layout and provide --{kind}-panel-marker')
        accepted['screenshot'] = self.screenshot(f'{len(self.report["steps"]):02d}-{kind}-native-panel')
        (self.out / f'{len(self.report["steps"]):02d}-{kind}-native-panel.json').write_text(
            json.dumps(self.layout(), ensure_ascii=False, indent=2))
        self.key('Back')
        self.expect_id('HdsTitleBar')
        accepted['cancelledAndReturnedToApp'] = True
        self.report['steps'][-1].setdefault('nativePanels', []).append(accepted)

    def share_cancel(self, filename):
        self.file_action(filename, '分享')
        self.cancel_native_panel('share', self.args.share_panel_marker)
        self.expect_text(filename)

    def run(self):
        try:
            with self.step('workspace-exact-qa-source'):
                self.open_workspace()
                self.exact_row(self.source_filename, True)
            extension = Path(self.source_filename).suffix.lower()
            if extension == '.pdf':
                action, output, text_tool = '提取页面', self.stem + '-extracted.pdf', False
            elif extension == '.csv':
                action, output, text_tool = 'CSV 转 JSON', self.stem + '-converted.json', True
            elif extension == '.json':
                action, output, text_tool = 'JSON 转 CSV', self.stem + '-converted.csv', True
            elif extension in ['.txt', '.md']:
                action, output, text_tool = '文本格式转换', self.stem + '-converted.md', True
            elif extension in ['.png', '.jpg', '.jpeg', '.webp', '.heic']:
                action, output, text_tool = '转换图片格式', self.stem + '-converted_1.jpg', False
            else:
                raise ValueError('Unsupported QA source extension: ' + extension)
            with self.step('continue-qa-source-through-another-tool'):
                self.continue_file(self.source_filename, action, True)
                stem = output[:-6] if extension in ['.png', '.jpg', '.jpeg', '.webp', '.heic'] else str(Path(output).with_suffix(''))
                self.set_result_name(stem)
                if extension in ['.png', '.jpg', '.jpeg', '.webp', '.heic']:
                    self.tap_text('PNG · 无损透明')
                    self.tap_text('JPEG · 小巧通用')
                self.tap_text('开始转换' if text_tool else '开始处理')
                self.wait_result(output, text_tool)
            with self.step('generated-file-native-share-cancel'):
                self.share_cancel(output)
            if extension in ['.png', '.jpg', '.jpeg', '.webp', '.heic']:
                with self.step('generated-jpeg-continues-to-real-a4-pdf'):
                    self.continue_file(output, '生成 PDF')
                    pdf_name = self.stem + '-images.pdf'
                    self.set_result_name(str(Path(pdf_name).with_suffix('')))
                    self.tap_text('开始处理')
                    self.wait_result(pdf_name)
                with self.step('generated-a4-pdf-native-share-cancel'):
                    self.share_cancel(pdf_name)
            elif not text_tool:
                with self.step('generated-pdf-native-save-cancel'):
                    self.file_action(output, '导出')
                    self.cancel_native_panel('save', self.args.save_panel_marker)
            with self.step('workspace-retains-source-and-generated-private-results'):
                self.back_to_main()
                self.open_workspace()
                for filename in [self.source_filename] + self.generated:
                    self.exact_row(filename, True)
                self.edge('up')
                self.report['retainedQaFiles'] = self.generated[:]
            self.report['status'] = 'pass'
        except Exception as error:
            self.report['status'] = 'fail'
            self.report['error'] = str(error)
            self.report['retainedQaFiles'] = self.generated[:]
            print('STOPPED:', error, file=sys.stderr, flush=True)
        finally:
            self.report['finishedAt'] = datetime.now().astimezone().isoformat()
            self.flush()
        return 0 if self.report['status'] == 'pass' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument('--filename', help='Exact known QA filename already present in LumiKit workspace')
    source.add_argument('--qa-report', help='Business-check JSON report containing a retained QA workspace filename')
    parser.add_argument('--device', default='127.0.0.1:5555')
    parser.add_argument('--output', default='docs/screenshots/emulator/file-workflow')
    parser.add_argument('--width', type=int, default=1320)
    parser.add_argument('--height', type=int, default=2848)
    parser.add_argument('--share-panel-marker', default='', help='Exact visible native share panel text, verified on this device')
    parser.add_argument('--save-panel-marker', default='', help='Exact visible native save picker text, verified on this device')
    return FileWorkflowCheck(parser.parse_args()).run()


if __name__ == '__main__':
    sys.exit(main())
