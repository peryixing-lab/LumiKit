#!/usr/bin/env python3
"""Nine-field LumiKit form checks through the real DevEco CLI UI.

Run after the other emulator scripts have returned LumiKit to its main tabs.
Imports BusinessCheck without running its main(), inheriting its current CLI,
safe tap bounds, gutter swipes, keyboard handling, and screenshot evidence.
Does not build, install, operate a device at import time, access app databases,
clear history, or delete pre-existing records. Only this run's QA form and its
answers are deleted. QA exports remain in the app workspace for inspection.

With --attachment-file-name, an exact pre-created QA filename must be visible in
the real system picker. The script imports it, saves/reopens the answer across a
process restart, and opens/cancels attachment export. No private paths are read.
Without that argument attachment coverage is limited to required validation and
picker cancellation. Attachment defaults are unsupported by the product. Only
this QA attachment field is then made optional for the separate defaults answer.
"""
import argparse
from datetime import datetime
import importlib.util
import json
from pathlib import Path
import re
import sys
import time


HELPER_PATH = Path(__file__).with_name('emulator-business-check.py')
HELPER_SPEC = importlib.util.spec_from_file_location('lumikit_business_helpers', HELPER_PATH)
if HELPER_SPEC is None or HELPER_SPEC.loader is None:
    raise ImportError('BusinessCheck helper could not be loaded: ' + str(HELPER_PATH))
HELPERS = importlib.util.module_from_spec(HELPER_SPEC)
HELPER_SPEC.loader.exec_module(HELPERS)  # Its __main__ guard prevents device operations.
BusinessCheck = HELPERS.BusinessCheck
flatten = HELPERS.flatten


FIELDS = [
    {'label': 'QAText', 'kind': 'text', 'default': 'DefaultText', 'answer': 'TextAnswer'},
    {'label': 'QAMulti', 'kind': 'textarea', 'default': 'DefaultMulti', 'answer': 'LineOne\nLineTwo'},
    {'label': 'QARadio', 'kind': 'radio', 'default': 'Alpha', 'answer': 'Beta'},
    {'label': 'QAMultiChoice', 'kind': 'checkbox', 'default': 'Alpha', 'answer': 'Alpha|Beta'},
    {'label': 'QADate', 'kind': 'date', 'default': '2026-10-16', 'answer': '2026-10-17'},
    {'label': 'QANumber', 'kind': 'number', 'default': '7', 'answer': '42'},
    {'label': 'QASelect', 'kind': 'select', 'default': 'Alpha', 'answer': 'Beta'},
    {'label': 'QARating', 'kind': 'rating', 'default': '3', 'answer': '4'},
    {'label': 'QAAttachment', 'kind': 'attachment', 'default': None, 'answer': None},
]


class FormFieldsCheck(BusinessCheck):
    def __init__(self, args):
        # Separate each run's screenshots and JSON, including two runs in one second.
        suffix = datetime.now().strftime('%Y%m%d-%H%M%S-%f')
        args.output = str(Path(args.output) / suffix)
        super().__init__(args)
        self.form_name = f'QA-LumiKit-{self.run_id}-NineFields-{suffix[-6:]}'
        self.pdf_names = [self.form_name + '_空白模板.pdf', self.form_name + '_回答.pdf']
        self.export_names = [self.form_name + '_Schema.json', self.form_name + '_数据模板.csv',
                             self.form_name + '_回答.csv', self.form_name + '_回答.json'] + self.pdf_names
        self.response_ids = []
        self.actual_response_id = None
        self.report.update({
            'qaNames': {'form': self.form_name}, 'modeScreenshots': [], 'exportEvidence': [],
            'fieldCoverage': {field['label']: {'type': field['kind'], 'required': 'pending',
                                             'description': 'pending', 'default': 'pending',
                                             'actualAnswer': 'pending'} for field in FIELDS},
            'limitations': [], 'retainedQaExports': [],
            'helperPath': str(HELPER_PATH), 'node': HELPERS.NODE, 'cli': HELPERS.CLI,
            'attachmentFileName': args.attachment_file_name,
        })
        self.report['notes'].append('JSON/CSV exports are checked through system picker and nonzero workspace file evidence; their content is not parsed by this UI script.')
        self.flush()

    def flush(self):
        (self.out / 'form-fields-results.json').write_text(
            json.dumps(self.report, ensure_ascii=False, indent=2))

    @staticmethod
    def help_text(field):
        return 'Help for ' + field['label']

    @staticmethod
    def label_matches(node, label):
        return node.get('text') in [label, label + ' *']

    def form_guard(self):
        self.expect_id('forms-page-edit')
        node = self.seek(lambda item: item.get('id') == 'forms-input-表单标题 *', 'own QA form title')
        if not self.form_name.startswith('QA-LumiKit-' + self.run_id) or node.get('text') != self.form_name:
            raise AssertionError('Refusing mutation: the selected schema is not this run\'s exact QA form')

    def scroll_edge(self, direction):
        previous, stable = None, 0
        for _ in range(24):
            self.swipe(direction)
            current = self.signature()
            stable = stable + 1 if current == previous else 0
            if stable >= 2:
                return
            previous = current
        raise AssertionError('Main Scroll did not reach a stable boundary: ' + direction)

    def capture_modes(self, label, mode, top_predicate, bottom_predicate):
        self.expect_id('forms-page-' + mode)
        entry = {'mode': mode, 'label': label}
        for position, direction, predicate in [('top', 'down', top_predicate),
                                                ('bottom', 'up', bottom_predicate)]:
            self.scroll_edge(direction)
            # A stable edge alone is insufficient: verify the expected first/last control.
            anchor = next((node for node in self.nodes() if predicate(node) and self.clickable_bounds(node)), None)
            if anchor is None:
                raise AssertionError(f'{mode} {position} anchor is outside the safe screenshot bounds')
            stem = label + '-' + position
            entry[position] = {'screenshot': self.screenshot(stem), 'anchor': {
                'id': anchor.get('id'), 'text': anchor.get('text'), 'bounds': anchor.get('bounds')},
                'stableScrollBoundary': True}
            (self.out / (stem + '.json')).write_text(json.dumps(self.layout(), ensure_ascii=False, indent=2))
        self.report['modeScreenshots'].append(entry)
        self.flush()

    def capture_editor(self, label):
        self.capture_modes(label, 'edit', lambda n: n.get('id') == 'forms-input-表单标题 *',
                           lambda n: n.get('id') == 'forms-delete')

    def capture_field_editor(self, label):
        self.capture_modes(label, 'field', lambda n: n.get('id') == 'forms-input-字段名称 *',
                           lambda n: n.get('id') == 'forms-field-save')

    def capture_fill(self, label, preview=False):
        self.capture_modes(label, 'preview' if preview else 'fill',
                           lambda n: n.get('id') == 'forms-answer-QAText',
                           (lambda n: n.get('text') == '＋ 选择本地附件') if preview else
                           (lambda n: n.get('id') == 'forms-submit'))

    def capture_responses(self, label, count):
        self.capture_modes(label, 'responses', lambda n: n.get('text') == f'{count} 份本地回答',
                           lambda n: str(n.get('id', '')).startswith('forms-response-card-'))

    def capture_response(self, label):
        self.capture_modes(label, 'response', lambda n: n.get('id') == 'forms-response-title',
                           lambda n: n.get('id') == 'forms-response-delete')

    def clear_input(self, key):
        # Empty strings are not passed through the CLI's positional text argument.
        self.tap_id(key)
        self.key(2072, 2017)
        self.key(2055)  # SDK KeyCode.KEYCODE_DEL: remove the selected text.
        self.key('Back')
        if self.find_text('放弃未保存的修改？') or self.find_text('放弃这次填写？'):
            self.tap_text('继续编辑')
        node = self.seek(lambda n: n.get('id') == key, key)
        if node.get('text', ''):
            raise AssertionError('Input did not clear: ' + key)

    def container(self, label, schema=False):
        self.seek(lambda n: self.label_matches(n, label), 'field label ' + label)
        candidates = []
        for node in self.nodes():
            children = flatten(node)
            if not any(self.label_matches(child, label) for child in children):
                continue
            if schema and not any(child.get('text') == '↑ 上移' for child in children):
                continue
            if not schema and not any(child.get('text') == 'Help for ' + label for child in children):
                continue
            candidates.append((len(children), node))
        if not candidates:
            raise AssertionError('Could not isolate the exact field container: ' + label)
        return min(candidates, key=lambda pair: pair[0])[1]

    def field_action(self, label, text):
        for _ in range(12):
            row = self.container(label, schema=True)
            target = next((node for node in flatten(row) if node.get('text') == text), None)
            if target and self.clickable_bounds(target):
                self.tap(target)
                return
            bounds = target.get('bounds', []) if target else []
            self.swipe('down' if bounds and bounds[1] < self.safe_top else 'up')
        raise AssertionError('Field action is not safely tappable: ' + label + ' / ' + text)

    def field_index(self, label):
        digits = [node.get('text') for node in flatten(self.container(label, schema=True))
                  if re.fullmatch(r'[1-9][0-9]*', str(node.get('text', '')))]
        if len(digits) != 1:
            raise AssertionError('Could not read an unambiguous field index: ' + label)
        return int(digits[0])

    def add_required_field(self, field):
        self.tap_id('forms-add-field')
        self.expect_id('forms-page-field')
        self.set_input('forms-input-字段名称 *', field['label'])
        self.tap_id('forms-type-' + field['kind'])
        self.set_input('forms-input-字段说明', self.help_text(field))
        self.tap_id('forms-field-required')  # A newly created field is known to be optional.
        if field['kind'] in ['radio', 'checkbox', 'select']:
            self.set_input('forms-field-options', 'Alpha\nBeta')
        if field['kind'] in ['text', 'textarea', 'date', 'number']:
            self.set_input('forms-input-默认值（可选）', field['default'])
        self.capture_field_editor('field-create-' + field['kind'])
        self.tap_id('forms-field-save')
        self.expect_id('forms-page-edit')
        self.expect_text(field['label'] + ' *')

    def configure_default(self, field):
        self.field_action(field['label'], '编辑')
        self.expect_id('forms-page-field')
        actual_name = self.seek(lambda n: n.get('id') == 'forms-input-字段名称 *', 'exact QA field').get('text')
        if actual_name != field['label']:
            raise AssertionError('Field edit opened a different field: ' + str(actual_name))
        if field['kind'] == 'attachment':
            self.tap_id('forms-field-required')  # Previously verified as required in the first fill.
            if self.find_id('forms-input-默认值（可选）'):
                raise AssertionError('Attachment unexpectedly exposes a text default value')
            self.report['fieldCoverage'][field['label']]['default'] = 'not_applicable_attachment'
        else:
            self.set_input('forms-input-默认值（可选）', field['default'])
            node = self.seek(lambda n: n.get('id') == 'forms-input-默认值（可选）', 'configured default')
            if node.get('text') != field['default']:
                raise AssertionError('Default value was not retained in the field editor')
        self.capture_field_editor('field-default-' + field['kind'])
        self.tap_id('forms-field-save')
        self.expect_id('forms-page-edit')

    def validate_required(self, field):
        self.tap_id('forms-submit')
        self.expect_id('forms-page-fill')
        message = self.seek(lambda n: n.get('id') == 'forms-validation-message', 'required field error').get('text')
        expected = '请填写「' + field['label'] + '」'
        if message != expected:
            raise AssertionError(f'Required validation expected {expected!r}, got {message!r}')
        self.report['fieldCoverage'][field['label']]['required'] = 'pass'

    def choose_select(self, label, option):
        self.container(label)
        # There is only one Select in this QA form; the stable unique label anchors it.
        select = self.seek(lambda n: n.get('type') == 'Select', 'QA dropdown Select')
        rect = select['bounds']
        self.tap(select)
        deadline = time.monotonic() + 8
        candidates = []
        while time.monotonic() < deadline:
            data = self.nodes()
            choices = []
            for node in data:
                if node.get('text') != option or not self.clickable_bounds(node):
                    continue
                bounds = node['bounds']
                x, y = (bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2
                if rect[0] <= x <= rect[2] and rect[1] <= y <= rect[3]:
                    continue  # Current Select label, never a popup choice.
                if str(node.get('id', '')).startswith('forms-'):
                    continue
                choices.append(node)
            menu_items = [node for node in data if 'MenuItem' in str(node.get('type', ''))
                          and self.clickable_bounds(node)
                          and any(child.get('text') == option for child in flatten(node))]
            if menu_items:
                candidates = menu_items
                break
            # Plain Text can also be a radio/checkbox label. Require a Menu ancestor.
            candidates = [node for node in choices if any('Menu' in str(parent.get('type', ''))
                          and node in flatten(parent) for parent in data)]
            if candidates:
                break
            time.sleep(.2)
        if not candidates:
            self.key('Back')
            raise AssertionError('Could not identify the real dropdown menu option safely: ' + option)
        candidates.sort(key=lambda node: len(flatten(node)))
        self.tap(candidates[0])
        self.expect_id('forms-page-fill')
        node = self.seek(lambda n: n.get('type') == 'Select', 'updated QA Select')
        if option not in [child.get('text') for child in flatten(node)]:
            raise AssertionError('Dropdown selection did not visibly update to ' + option)

    def choose_rating(self, rating):
        for _ in range(12):
            row = self.container('QARating')
            buttons = [node for node in flatten(row) if node.get('type') == 'Button'
                       and any(child.get('text') == '★' for child in flatten(node))]
            # Native Button may expose its label directly or as a child Text.
            unique = {tuple(node.get('bounds', [])): node for node in buttons if len(node.get('bounds', [])) == 4}
            buttons = sorted(unique.values(), key=lambda node: node['bounds'][0])
            if len(buttons) != 5:
                raise AssertionError('Rating field does not contain five distinct star buttons')
            target = buttons[rating - 1]
            if self.clickable_bounds(target):
                self.tap(target)
                return
            self.swipe('down' if target['bounds'][1] < self.safe_top else 'up')
        raise AssertionError('Rating control is outside the safe tap area')

    def fill_field(self, field, from_defaults=False):
        kind, label = field['kind'], field['label']
        if kind in ['text', 'textarea', 'date', 'number']:
            self.set_input('forms-answer-' + label, field['answer'])
            if kind == 'date':
                # Verify invalid calendar dates are rejected, then restore a valid value.
                self.set_input('forms-answer-' + label, '2026-02-30')
                self.tap_id('forms-submit')
                self.expect_text('「QADate」需要有效的 YYYY-MM-DD 日期')
                self.set_input('forms-answer-' + label, field['answer'])
        elif kind == 'radio':
            self.tap_id('forms-choice-' + label + '-Beta')
        elif kind == 'checkbox':
            if not from_defaults:
                self.tap_id('forms-choice-' + label + '-Alpha')
            self.tap_id('forms-choice-' + label + '-Beta')
        elif kind == 'select':
            self.choose_select(label, 'Beta')
        elif kind == 'rating':
            self.choose_rating(4)

    def attachment_picker_cancel(self):
        self.tap_text('＋ 选择本地附件')
        deadline, picker = time.monotonic() + 15, False
        while time.monotonic() < deadline:
            data = self.nodes()
            texts = [node.get('text', '') for node in data]
            if not any(node.get('id') == 'forms-page-fill' for node in data) and any(
                    term in '\n'.join(texts) for term in ['文件', '最近', '浏览', '取消', '选择', 'File', 'Recent']):
                picker = True
                break
            time.sleep(.3)
        if not picker:
            raise AssertionError('The real attachment DocumentViewPicker was not observed')
        self.report['attachmentPickerScreenshot'] = self.screenshot('attachment-system-picker-cancel')
        (self.out / 'attachment-system-picker-cancel.json').write_text(json.dumps(self.layout(), ensure_ascii=False, indent=2))
        self.key('Back')
        self.expect_id('forms-page-fill')
        self.validate_required(FIELDS[-1])  # Cancellation must not satisfy attachment required validation.
        self.report['fieldCoverage']['QAAttachment']['pickerCancellation'] = 'pass'
        if not self.args.attachment_file_name:
            self.report['fieldCoverage']['QAAttachment'].update({
                'actualAnswer': 'not_tested_file_selection', 'storedAnswer': 'empty_optional_only'})
            self.report['limitations'].append(
                'Attachment: required validation and the real picker cancellation are verified. '
                'No file was supplied with --attachment-file-name; file selection, attachment export, and attachment content are untested. '
                'Only this QA field is then made optional so the other eight field types can be saved.')

    def pick_qa_attachment(self):
        filename = self.args.attachment_file_name
        if not filename or not filename.startswith(('QA-', 'QA_')) or any(char in filename for char in '/\\\r\n'):
            raise AssertionError('Refusing to select a file without an exact QA filename')
        self.tap_text('＋ 选择本地附件')
        deadline, target = time.monotonic() + 15, None
        while time.monotonic() < deadline:
            data = self.nodes()
            if not any(node.get('id') == 'forms-page-fill' for node in data):
                target = next((node for node in data if node.get('text') == filename and self.clickable_bounds(node)), None)
                if target:
                    break
            time.sleep(.3)
        if target is None:
            raise AssertionError('Exact QA attachment is not safely visible in the system picker: ' + filename +
                                 '. Prepare the QA file in the picker\'s current location; no unrelated file will be selected.')
        self.report['attachmentSelectScreenshot'] = self.screenshot('attachment-exact-qa-file')
        self.tap(target)
        deadline, confirmed = time.monotonic() + 15, False
        while time.monotonic() < deadline:
            data = self.nodes()
            if any(node.get('id') == 'forms-page-fill' for node in data):
                break
            # DocumentViewPicker versions either return on a file tap or require
            # an explicit native confirmation after that exact file was selected.
            confirm = next((node for node in data if node.get('type') == 'Button'
                            and any(child.get('text') in ['打开', '选择', '确定', '完成', 'Open', 'Select'] for child in flatten(node))
                            and self.clickable_bounds(node)), None)
            if confirm and not confirmed:
                self.report['attachmentConfirmScreenshot'] = self.screenshot('attachment-picker-confirm')
                self.tap(confirm)
                confirmed = True
            time.sleep(.3)
        self.expect_id('forms-page-fill')
        row = self.container('QAAttachment')
        if filename not in [node.get('text') for node in flatten(row)]:
            raise AssertionError('Exact selected QA attachment was not added to the answer')
        self.report['fieldCoverage']['QAAttachment'].update({'actualAnswer': 'selected_pending_save',
                                                             'selectedFileName': filename})

    def check_descriptions(self):
        for field in FIELDS:
            self.expect_text(self.help_text(field))
            self.report['fieldCoverage'][field['label']]['description'] = 'pass'

    def check_default_widgets(self):
        for field in FIELDS:
            if field['kind'] in ['text', 'textarea', 'date', 'number']:
                node = self.seek(lambda n: n.get('id') == 'forms-answer-' + field['label'], 'default widget ' + field['label'])
                if node.get('text') != field['default']:
                    raise AssertionError('Default is not rendered: ' + field['label'])
            elif field['kind'] in ['radio', 'checkbox']:
                node = self.seek(lambda n: n.get('id') == 'forms-choice-' + field['label'] + '-Alpha', 'default choice')
                marker = '●' if field['kind'] == 'radio' else '☑'
                if marker not in [child.get('text') for child in flatten(node)]:
                    raise AssertionError('Default choice is not selected: ' + field['label'])
            elif field['kind'] == 'select':
                self.container(field['label'])
                node = self.seek(lambda n: n.get('type') == 'Select', 'default dropdown')
                if 'Alpha' not in [child.get('text') for child in flatten(node)]:
                    raise AssertionError('Default dropdown value is not rendered')
        # Rating defaults are proved by the saved answer; star color alone is not a state assertion.

    def open_response(self, expected, evidence_label, attachment_name=None, response_id=None):
        self.expect_id('forms-page-responses')
        # capture_responses ends at the bottom, where the older answer is visible.
        # Resolve the first card in the actual ordered list, then seek that exact ID.
        self.scroll_edge('down')
        cards = [node for node in self.nodes() if str(node.get('id', '')).startswith('forms-response-card-')]
        if not cards:
            raise AssertionError('The own QA response list is empty')
        target_id = response_id or cards[0].get('id')
        card = self.seek(lambda n: n.get('id') == target_id, 'exact own QA answer')
        response_id = card.get('id')
        self.tap(card)
        self.expect_id('forms-page-response')
        title = self.seek(lambda n: n.get('id') == 'forms-response-title', 'exact saved QA form title').get('text')
        if title != self.form_name:
            raise AssertionError('Opened an answer belonging to a different form')
        for field in FIELDS[:-1]:
            node = self.seek(lambda n: n.get('id') == 'forms-value-' + field['label'], 'saved ' + field['label'])
            actual = node.get('text')
            if actual != expected[field['label']]:
                raise AssertionError(f'Saved {field["label"]}: expected {expected[field["label"]]!r}, got {actual!r}')
        attachment = self.container_for_response_attachment(attachment_name)
        expected_attachment = attachment_name or '未填写'
        if expected_attachment not in [node.get('text') for node in flatten(attachment)]:
            raise AssertionError('Saved attachment value differs from the exact QA filename')
        self.capture_response(evidence_label)
        self.response_ids.append(response_id)
        return response_id

    def container_for_response_attachment(self, attachment_name=None):
        self.expect_text('QAAttachment')
        candidates = []
        for node in self.nodes():
            descendants = flatten(node)
            texts = [child.get('text') for child in descendants]
            if 'QAAttachment' in texts and (attachment_name or '未填写') in texts:
                candidates.append((len(descendants), node))
        if not candidates:
            raise AssertionError('No saved optional attachment field is visible')
        return min(candidates, key=lambda pair: pair[0])[1]

    def back_to_editor(self):
        if self.find_id('forms-page-response'):
            self.key('Back')
            self.expect_id('forms-page-responses')
        if self.find_id('forms-page-responses'):
            self.key('Back')
        self.expect_id('forms-page-edit')

    def export_and_cancel(self, title, filename, button_id=None, expected_mode='edit'):
        if button_id:
            self.tap_id(button_id)
        else:
            self.tap_text(title)
        deadline, picker = time.monotonic() + 20, False
        while time.monotonic() < deadline:
            data = self.nodes()
            text = '\n'.join(str(node.get('text', '')) for node in data)
            own_page = any(str(node.get('id', '')).startswith('forms-page-') for node in data)
            if not own_page and any(word in text for word in ['保存', '位置', '文件', 'Save', 'Location']):
                picker = True
                break
            time.sleep(.3)
        if not picker:
            raise AssertionError('Export did not open the real system save picker: ' + title)
        stem = 'export-picker-' + re.sub('[^a-zA-Z0-9_-]', '-', title)
        screenshot = self.screenshot(stem)
        (self.out / (stem + '.json')).write_text(json.dumps(self.layout(), ensure_ascii=False, indent=2))
        self.key('Back')
        self.expect_id('forms-page-' + expected_mode)
        self.report['exportEvidence'].append({'name': filename, 'systemPickerObserved': True,
                                               'pickerCancelled': True, 'pickerScreenshot': screenshot,
                                               'workspaceNonzeroFile': 'pending' if filename in self.export_names else 'existing_imported_attachment'})

    def workspace_row(self, filename):
        self.expect_text(filename)
        candidates = []
        for node in self.nodes():
            descendants = flatten(node)
            texts = [child.get('text') for child in descendants]
            if filename in texts and '移除副本' in texts and '导出' in texts and '分享' in texts:
                candidates.append((len(descendants), node))
        if not candidates:
            raise AssertionError('Exact generated QA workspace row is missing: ' + filename)
        return min(candidates, key=lambda pair: pair[0])[1]

    def check_exports_in_workspace(self):
        with self.step('workspace-open-qa-exports'):
            self.ensure_main()
            self.tap_id('nav-tab-3')
            self.tap_text('文件工作区')
            self.expect_text('你的文件，集中有序')
        for index, filename in enumerate(self.export_names):
            with self.step(f'workspace-export-{index + 1}-real-nonempty-file') as entry:
                if not filename.startswith(self.form_name + '_'):
                    raise AssertionError('Refusing workspace action outside the exact QA form prefix')
                row = self.workspace_row(filename)
                sizes = [node.get('text', '') for node in flatten(row)
                         if re.fullmatch(r'[0-9.]+\s*[KMG]?B', node.get('text', ''))]
                if not sizes or not any(float(re.match(r'[0-9.]+', size).group()) > 0 for size in sizes):
                    raise AssertionError('Export does not exist as a nonzero workspace file: ' + filename)
                entry.update({'filename': filename, 'nonzeroWorkspaceSize': sizes})
                export = next(item for item in self.report['exportEvidence'] if item['name'] == filename)
                export.update({'workspaceNonzeroFile': True, 'sizeLabels': sizes})
                self.report['retainedQaExports'].append(filename)
                if filename.endswith('.pdf'):
                    self.row_action(filename, '预览')
                    self.expect_text('文件预览')
                    time.sleep(.8)
                    if 'PDF 预览失败' in self.alltext():
                        raise AssertionError('Nine-field PDF preview failed: ' + filename)
                    entry['previewScreenshot'] = self.screenshot(f'workspace-pdf-{index + 1}-preview')
                    export['previewOpened'] = True
                    self.tap_text('收起')
        self.back_to_main()

    def forms(self):
        with self.step('nine-fields-create-own-qa-schema'):
            self.open_tool('forms')
            self.tap_id('forms-create')
            self.set_input('forms-input-表单标题 *', self.form_name)
        for field in FIELDS:
            with self.step('create-required-' + field['kind']):
                self.add_blank_required_field(field)
        with self.step('field-order-up-and-down') as entry:
            before = self.field_index('QANumber')
            if before != 6:
                raise AssertionError('Created fields are not in their insertion order')
            self.field_action('QANumber', '↑ 上移')
            if self.field_index('QANumber') != before - 1:
                raise AssertionError('Move up did not update the visible field index')
            self.field_action('QANumber', '↓ 下移')
            if self.field_index('QANumber') != before:
                raise AssertionError('Move down did not restore the field index')
            entry['fieldIndices'] = [before, before - 1, before]
        with self.step('save-nine-fields-schema-and-editor-screenshots'):
            self.tap_id('forms-save-schema')
            self.expect_id('forms-delete')
            self.report['created'].append({'kind': 'form', 'name': self.form_name})
            self.capture_editor('schema-nine-required')
        with self.step('preview-nine-required-fields'):
            self.tap_id('forms-preview')
            self.expect_id('forms-page-preview')
            self.check_descriptions()
            self.capture_fill('preview-nine-required', preview=True)
            if self.find_id('forms-submit'):
                raise AssertionError('Preview must not expose a save-answer button')
            self.key('Back')
            self.expect_id('forms-page-edit')
        with self.step('fill-nine-required-top-and-bottom'):
            self.tap_id('forms-fill')
            self.expect_id('forms-page-fill')
            self.capture_fill('fill-nine-required')
        for field in FIELDS:
            with self.step('required-validation-' + field['kind']):
                self.validate_required(field)
                if field['kind'] != 'attachment':
                    self.fill_field(field)
                else:
                    self.attachment_picker_cancel()
        with self.step('discard-only-own-unsaved-qa-answer'):
            self.key('Back')
            self.expect_text('放弃这次填写？')
            self.tap_text('放弃修改')
            self.expect_id('forms-page-edit')
        for field in FIELDS:
            with self.step('configure-default-' + field['kind']):
                self.configure_default(field)
        with self.step('save-defaults-and-optional-attachment'):
            self.tap_id('forms-save-schema')
            self.expect_id('forms-delete')
            self.capture_editor('schema-with-defaults')
        with self.step('preview-default-values-and-help'):
            self.tap_id('forms-preview')
            self.expect_id('forms-page-preview')
            self.check_descriptions()
            self.check_default_widgets()
            self.capture_fill('preview-with-defaults', preview=True)
            self.key('Back')
            self.expect_id('forms-page-edit')
        with self.step('save-answer-with-unmodified-defaults'):
            self.tap_id('forms-fill')
            self.expect_id('forms-page-fill')
            self.check_default_widgets()
            self.capture_fill('fill-default-values')
            self.tap_id('forms-submit')
            self.expect_id('forms-page-responses')
            self.expect_text('1 份本地回答')
            self.capture_responses('response-list-defaults', 1)
        with self.step('verify-all-eight-supported-defaults-in-saved-answer'):
            self.open_latest_response({field['label']: field['default'] for field in FIELDS[:-1]}, 'response-defaults')
            for field in FIELDS[:-1]:
                self.report['fieldCoverage'][field['label']]['default'] = 'pass_saved_answer'
            self.back_to_editor()
        with self.step('fill-all-eight-supported-field-types'):
            self.tap_id('forms-fill')
            self.expect_id('forms-page-fill')
            for field in FIELDS[:-1]:
                self.fill_field(field, from_defaults=True)
            self.capture_fill('fill-actual-values')
            self.tap_id('forms-submit')
            self.expect_id('forms-page-responses')
            self.expect_text('2 份本地回答')
            self.capture_responses('response-list-two-answers', 2)
        with self.step('verify-saved-nine-field-answer'):
            self.open_latest_response({field['label']: field['answer'] for field in FIELDS[:-1]}, 'response-actual-values')
            for field in FIELDS[:-1]:
                self.report['fieldCoverage'][field['label']]['actualAnswer'] = 'pass_saved_answer'
        with self.step('export-nine-field-answer-pdf'):
            self.export_and_cancel('Response-PDF', self.pdf_names[1], 'forms-export-response-pdf')
            self.back_to_editor()
        for title, filename in zip(['JSON Schema', 'CSV 模板', '回答 CSV', '回答 JSON'], self.export_names[:4]):
            with self.step('export-' + {'JSON Schema': 'json-schema', 'CSV 模板': 'csv-template',
                                      '回答 CSV': 'response-csv', '回答 JSON': 'response-json'}[title]):
                self.export_and_cancel(title, filename)
        with self.step('export-nine-field-blank-pdf'):
            self.export_and_cancel('Template-PDF', self.pdf_names[0], 'forms-export-template-pdf')
        with self.step('two-answers-persist-after-process-restart'):
            self.restart_app()  # All QA schemas/answers were saved; no unknown draft is abandoned.
            self.open_tool('forms')
            self.set_input('forms-search', self.form_name)
            self.tap_record('forms-card-', self.form_name)
            self.form_guard()
            self.tap_id('forms-responses')
            self.expect_text('2 份本地回答')
            self.open_latest_response({field['label']: field['answer'] for field in FIELDS[:-1]}, 'response-after-restart')
            self.back_to_editor()
        with self.step('delete-only-this-run-qa-schema-and-two-answers'):
            self.form_guard()
            self.tap_id('forms-delete')
            self.expect_text('表单定义及其本地回答将一起删除，此操作无法撤销。')
            self.tap_text('删除')
            self.expect_id('forms-page-list')
            self.set_input('forms-search', self.form_name)
            if self.record_visible('forms-card-', self.form_name):
                raise AssertionError('Deleted QA form is still in the exact-name search results')
            self.report['deleted'].append({'kind': 'form', 'name': self.form_name})
            self.report['deletedAnswerIds'] = sorted(set(self.response_ids))
            self.back_to_main()
        self.check_exports_in_workspace()

    def run(self):
        try:
            with self.step('precondition-main-tabs'):
                self.ensure_main()
            self.forms()
            self.report['status'] = 'pass_with_limitations' if self.report['limitations'] else 'pass'
        except Exception as error:
            self.report['status'] = 'fail'
            self.report['error'] = str(error)
            self.report['remainingQaRecords'] = [entry for entry in self.report['created']
                                                  if entry not in self.report['deleted']]
            print('STOPPED:', error, file=sys.stderr, flush=True)
        finally:
            self.report['finishedAt'] = datetime.now().astimezone().isoformat()
            self.flush()
            print(json.dumps({'status': self.report['status'], 'report': str(self.out / 'form-fields-results.json'),
                              'qaForm': self.form_name, 'limitations': self.report['limitations']},
                             ensure_ascii=False), flush=True)
        return 1 if self.report['status'] == 'fail' else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='127.0.0.1:5555')
    parser.add_argument('--output', default='docs/screenshots/emulator/form-fields')
    parser.add_argument('--width', type=int, default=1320, help='Actual screenshot width in pixels')
    parser.add_argument('--height', type=int, default=2848, help='Actual screenshot height in pixels')
    args = parser.parse_args()
    args.only = 'forms'
    return FormFieldsCheck(args).run()


if __name__ == '__main__':
    sys.exit(main())
