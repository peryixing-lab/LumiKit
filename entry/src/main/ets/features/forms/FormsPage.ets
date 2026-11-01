import { TextAreaPageScroll } from '../../core/TextAreaPageScroll';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { LumiHelpNavigation } from '../help/HelpNavigation';
import { common } from '@kit.AbilityKit';
import { curves, LengthMetrics } from '@kit.ArkUI';
import { StorageService, BackupDocument } from '../../core/StorageService';
import { FileService } from '../../core/FileService';
import { InventoryFiles } from '../inventory/InventoryFiles';
import { isValidDate, localDate, LocalAttachment, newLocalId } from '../inventory/InventoryModels';
import { buildJsonSchema, csvCell, FieldAnswer, FIELD_NAMES, FIELD_TYPES, fieldTypeName, FormField,
  FormResponse, LocalForm, responseCsv, validForm, validResponse } from './FormModels';
import { LumiFormDraft, validFormDraft, copyForm, formTemplate } from './FormDrafts';
import { LumiRecordRouteParam } from '../../core/IncomingRequest';
import { FormPdfService } from './FormPdfService';

@Builder
export function formsBuilder() {
  FormsPage()
}

@Component
export struct FormsPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State private forms: LocalForm[] = [];
  @State private responses: FormResponse[] = [];
  @State @Watch('resetPagePosition') private mode: string = 'list';
  @State @Watch('scheduleDraft') private draft: LocalForm = new LocalForm();
  @State @Watch('scheduleDraft') private field: FormField = new FormField();
  @State @Watch('scheduleDraft') private optionsText: string = '';
  @State @Watch('scheduleDraft') private answers: FieldAnswer[] = [];
  @State private selectedResponse: FormResponse = new FormResponse();
  @State private query: string = '';
  @State private message: string = '';
  @State private busy: boolean = false;
  @State private ready: boolean = false;
  @State private savedDraft: LumiFormDraft | undefined = undefined;
  private draftTimer: number = -1;
  private dragFieldId: string = '';
  private recordId: string = '';
  private confirmingBack: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private readonly pageScroller: Scroller = new Scroller();
  private readonly descriptionScroll: TextAreaPageScroll = new TextAreaPageScroll();
  private readonly optionsScroll: TextAreaPageScroll = new TextAreaPageScroll();
  private readonly answerScrolls: Map<string, TextAreaPageScroll> = new Map();

  private answerScroll(id: string): TextAreaPageScroll {
    let modifier = this.answerScrolls.get(id);
    if (!modifier) { modifier = new TextAreaPageScroll(); this.answerScrolls.set(id, modifier); }
    return modifier;
  }

  aboutToAppear(): void {
    this.load();
  }

  private resetPagePosition(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.pageScroller.scrollEdge(Edge.Top);
  }

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }

  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message: message }); }

  private async load(): Promise<void> {
    try {
      const forms = JSON.parse(await StorageService.getValue('forms.schemas', '[]')) as LocalForm[];
      const responses = JSON.parse(await StorageService.getValue('forms.responses', '[]')) as FormResponse[];
      if (!Array.isArray(forms) || !forms.every(validForm) || !Array.isArray(responses) || !responses.every(validResponse)) {
        throw new Error('表单格式无效');
      }
      this.forms = forms;
      this.responses = responses;
      const saved = JSON.parse(await StorageService.getValue('forms.autodraft', 'null')) as LumiFormDraft;
      this.savedDraft = saved && validFormDraft(saved) ? saved : undefined;
      const selected = forms.find((form: LocalForm) => form.id === this.recordId);
      if (selected) { this.open(selected); }
    } catch (error) { this.message = '本地表单暂时无法读取，请返回后重试。'; }
    this.ready = true;
  }

  aboutToDisappear(): void { this.flushDraft().catch(() => {}); }
  private scheduleDraft(): void {
    if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); }
    if (!['edit', 'field', 'fill'].includes(this.mode)) { return; }
    this.draftTimer = setTimeout(() => { this.flushDraft().catch(() => { this.message = '草稿未能保存，请手动保存后离开'; }); }, 350);
  }
  private async flushDraft(): Promise<void> {
    if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); this.draftTimer = -1; }
    if (!['edit', 'field', 'fill'].includes(this.mode) || !this.draft.id) { return; }
    const saved = new LumiFormDraft(); saved.schema = this.draft; saved.answers = this.answers; saved.field = this.field;
    saved.optionsText = this.optionsText; saved.mode = this.mode; saved.savedAt = Date.now();
    await StorageService.setValue('forms.autodraft', JSON.stringify(saved));
    this.savedDraft = JSON.parse(JSON.stringify(saved)) as LumiFormDraft;
  }
  private resumeDraft(): void {
    if (!this.savedDraft) { return; }
    const saved = JSON.parse(JSON.stringify(this.savedDraft)) as LumiFormDraft;
    this.draft = saved.schema; this.answers = saved.answers; this.field = saved.field; this.optionsText = saved.optionsText;
    this.mode = saved.mode; this.message = '';
  }
  private async discardDraft(): Promise<void> {
    await StorageService.setValue('forms.autodraft', 'null'); this.savedDraft = undefined;
  }
  private useTemplate(kind: number): void { this.draft = formTemplate(kind); this.mode = 'edit'; this.scheduleDraft(); }
  private duplicateForm(): void { this.draft = copyForm(this.draft); this.mode = 'edit'; this.scheduleDraft(); }
  private dropField(id: string): void {
    const from = this.draft.fields.findIndex((entry: FormField) => entry.id === this.dragFieldId);
    const to = this.draft.fields.findIndex((entry: FormField) => entry.id === id);
    if (from < 0 || to < 0 || from === to) { return; }
    this.moveField(from, to - from); this.dragFieldId = '';
  }

  private visibleForms(): LocalForm[] {
    const query = this.query.trim().toLowerCase();
    return this.forms.filter((form: LocalForm) => `${form.title} ${form.description}`.toLowerCase().includes(query));
  }

  private formResponses(id: string): FormResponse[] {
    return this.responses.filter((response: FormResponse) => response.formId === id);
  }

  private open(form: LocalForm): void {
    this.draft = JSON.parse(JSON.stringify(form)) as LocalForm;
    this.message = '';
    this.mode = 'edit';
  }

  private createForm(): void {
    this.draft = new LocalForm();
    this.draft.id = newLocalId('form');
    this.draft.createdAt = Date.now();
    this.message = '';
    this.mode = 'edit';
  }

  private async saveSchema(showToast: boolean = true): Promise<boolean> {
    if (!this.draft.title.trim()) { this.message = '请填写表单标题'; return false; }
    this.busy = true;
    this.draft.title = this.draft.title.trim();
    this.draft.updatedAt = Date.now();
    const next = [this.draft].concat(this.forms.filter((form: LocalForm) => form.id !== this.draft.id));
    try {
      await StorageService.setValue('forms.schemas', JSON.stringify(next));
      this.forms = JSON.parse(JSON.stringify(next)) as LocalForm[];
      this.message = '';
      if (showToast) { this.toast('表单已保存'); }
      try { await StorageService.addHistory('forms', '保存本地表单', `${this.draft.fields.length} 个字段`); } catch (error) {}
      return true;
    } catch (error) { this.message = '保存失败，请重试'; return false; }
    finally { this.busy = false; }
  }

  private editField(field?: FormField): void {
    this.field = field ? JSON.parse(JSON.stringify(field)) as FormField : new FormField();
    if (!field) { this.field.id = newLocalId('field'); }
    this.optionsText = this.field.options.join('\n');
    this.message = '';
    this.mode = 'field';
  }

  private saveField(): void {
    if (!this.field.label.trim()) { this.message = '请填写字段名称'; return; }
    const options = this.optionsText.split('\n').map((value: string) => value.trim()).filter((value: string) => value.length > 0);
    if (['radio', 'checkbox', 'select'].includes(this.field.type)) {
      if (options.length < 2) { this.message = '选择类型至少需要两个选项，每行填写一个'; return; }
      if (options.some((value: string, index: number) => options.indexOf(value) !== index || value.includes('|'))) {
        this.message = '选项不可重复，也不能包含竖线 |'; return;
      }
    }
    this.field.options = options;
    this.field.label = this.field.label.trim();
    const defaultValue = this.field.defaultValue;
    if (defaultValue && this.field.type === 'date' && !isValidDate(defaultValue)) {
      this.message = '日期默认值请使用 YYYY-MM-DD'; return;
    }
    if (defaultValue && ['number', 'rating'].includes(this.field.type) && !Number.isFinite(Number(defaultValue))) {
      this.message = '数字默认值格式不正确'; return;
    }
    if (defaultValue && this.field.type === 'rating' && (!Number.isInteger(Number(defaultValue)) || Number(defaultValue) < 1 || Number(defaultValue) > 5)) {
      this.message = '评分默认值需为 1–5 的整数'; return;
    }
    if (defaultValue && ['radio', 'select'].includes(this.field.type) && !options.includes(defaultValue)) {
      this.message = '默认值需要与一个选项完全一致'; return;
    }
    if (defaultValue && this.field.type === 'checkbox' && defaultValue.split('|').some((value: string) => !options.includes(value))) {
      this.message = '多选默认值请使用竖线 | 分隔已有选项'; return;
    }
    const index = this.draft.fields.findIndex((entry: FormField) => entry.id === this.field.id);
    const fields = this.draft.fields.slice();
    if (index >= 0) { fields[index] = this.field; } else { fields.push(this.field); }
    this.draft.fields = fields;
    this.mode = 'edit';
    this.message = '';
  }

  private moveField(index: number, offset: number): void {
    const destination = index + offset;
    if (destination < 0 || destination >= this.draft.fields.length) { return; }
    const fields = this.draft.fields.slice();
    const item = fields.splice(index, 1)[0];
    fields.splice(destination, 0, item);
    this.draft.fields = fields;
  }

  private async startFill(preview: boolean): Promise<void> {
    if (!this.draft.fields.length) { this.message = '先添加至少一个字段，再预览或填写'; return; }
    if (!preview && !await this.saveSchema(false)) { return; }
    this.answers = this.draft.fields.map((field: FormField) => {
      const answer = new FieldAnswer();
      answer.fieldId = field.id;
      answer.label = field.label;
      answer.type = field.type;
      answer.value = field.defaultValue;
      return answer;
    });
    this.message = '';
    this.mode = preview ? 'preview' : 'fill';
  }

  private answer(field: FormField): FieldAnswer {
    return this.answers.find((answer: FieldAnswer) => answer.fieldId === field.id) || new FieldAnswer();
  }

  private setAnswer(field: FormField, value: string): void {
    this.answers = this.answers.map((answer: FieldAnswer) => {
      if (answer.fieldId === field.id) { answer.value = value; }
      return answer;
    });
  }

  private isChosen(field: FormField, value: string): boolean {
    return this.answer(field).value.split('|').includes(value);
  }

  private toggleChoice(field: FormField, value: string): void {
    const selected = this.answer(field).value.split('|').filter((entry: string) => entry.length > 0);
    this.setAnswer(field, selected.includes(value) ? selected.filter((entry: string) => entry !== value).join('|') : selected.concat([value]).join('|'));
  }

  private async answerAttachment(field: FormField): Promise<void> {
    this.busy = true;
    try {
      const attachments = await InventoryFiles.attach(this.context());
      this.answers = this.answers.map((answer: FieldAnswer) => {
        if (answer.fieldId === field.id) { answer.attachments = answer.attachments.concat(attachments); }
        return answer;
      });
    } catch (error) { this.toast((error as Error).message || '附件未能添加'); }
    finally { this.busy = false; }
  }

  private pickDate(field: FormField): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(1900, 0, 1), end: new Date(2100, 11, 31), selected: new Date(), lunar: false,
      onDateAccept: (value: Date) => { this.setAnswer(field, localDate(value)); }
    });
  }

  private async submit(): Promise<void> {
    for (const field of this.draft.fields) {
      const answer = this.answer(field);
      if (field.required && (field.type === 'attachment' ? answer.attachments.length === 0 : !answer.value.trim())) {
        this.message = `请填写「${field.label}」`; return;
      }
      if (answer.value && field.type === 'date' && !isValidDate(answer.value)) {
        this.message = `「${field.label}」需要有效的 YYYY-MM-DD 日期`; return;
      }
      if (answer.value && field.type === 'number' && !Number.isFinite(Number(answer.value))) {
        this.message = `「${field.label}」需要有效的数字`; return;
      }
    }
    this.busy = true;
    const response = new FormResponse();
    response.id = newLocalId('response');
    response.formId = this.draft.id;
    response.formTitle = this.draft.title;
    response.submittedAt = `${localDate(new Date())} ${new Date().toTimeString().substring(0, 8)}`;
    response.answers = this.answers;
    const next = [response].concat(this.responses);
    try {
      await StorageService.setValue('forms.responses', JSON.stringify(next));
      this.responses = next;
      this.message = '';
      this.mode = 'responses';
      await this.discardDraft();
      this.toast('回答已保存在本机');
      try { await StorageService.addHistory('forms', '提交本地表单', `${this.draft.fields.length} 个字段`); } catch (error) {}
    } catch (error) { this.message = '回答未能保存，请重试'; }
    finally { this.busy = false; }
  }

  private async exportData(format: string): Promise<void> {
    if (!await this.saveSchema(false)) { return; }
    let content = '';
    let suffix = 'json';
    let label = 'Schema';
    if (format === 'schema') { content = JSON.stringify(buildJsonSchema(this.draft), null, 2); }
    else if (format === 'template') {
      suffix = 'csv'; label = '数据模板';
      content = '\uFEFF' + this.draft.fields.map((field: FormField) => csvCell(field.label)).join(',') + '\r\n';
    } else if (format === 'csv') {
      suffix = 'csv'; label = '回答';
      content = responseCsv(this.draft, this.formResponses(this.draft.id));
    } else {
      label = '回答';
      content = JSON.stringify(this.formResponses(this.draft.id), null, 2);
    }
    this.busy = true;
    try {
      const filename = `${this.draft.title.replace(/[\\/:*?"<>|]/g, '_')}_${label}.${suffix}`;
      const path = await InventoryFiles.save(this.context(), content, filename, suffix);
      if (path) {
        this.toast('已导出');
        try { await StorageService.addHistory('forms', `导出表单${label}`, suffix.toUpperCase(), path); } catch (error) {}
      }
    } catch (error) { this.toast((error as Error).message || '导出失败，请重试'); }
    finally { this.busy = false; }
  }

  private async deleteForm(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除表单', message: '表单定义及其本地回答将一起删除，此操作无法撤销。',
      buttons: [{ text: '取消', color: '#66758A' }, { text: '删除', color: '#D74747' }]
    });
    if (result.index !== 1) { return; }
    this.busy = true;
    try {
      const forms = this.forms.filter((form: LocalForm) => form.id !== this.draft.id);
      const responses = this.responses.filter((response: FormResponse) => response.formId !== this.draft.id);
      if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); this.draftTimer = -1; }
      const changes: BackupDocument[] = [
        { key: 'forms.responses', value: JSON.stringify(responses) },
        { key: 'forms.schemas', value: JSON.stringify(forms) }
      ];
      const removeDraft = this.savedDraft?.schema.id === this.draft.id;
      if (removeDraft) { changes.push({ key: 'forms.autodraft', value: 'null' }); }
      await StorageService.setValues(changes);
      this.responses = responses; this.forms = forms;
      if (removeDraft) { this.savedDraft = undefined; }
      this.mode = 'list';
    } catch (error) { this.toast('删除未完成，请重试'); }
    finally { this.busy = false; }
  }

  private async exportPdf(response?: FormResponse): Promise<void> {
    if (!response && !await this.saveSchema(false)) { return; }
    this.busy = true;
    try {
      const path = await FormPdfService.create(this.context(), this.getUIContext(), this.draft, response);
      try { await StorageService.addHistory('forms', response ? '导出回答 PDF' : '导出空白表单 PDF', 'A4 文本 PDF，可打印', path); } catch (error) {}
      await FileService.exportFile(this.context(), path, `${response ? response.formTitle : this.draft.title}_${response ? '回答' : '空白模板'}.pdf`);
      this.toast('PDF 已导出，可使用系统 PDF 应用打印');
    } catch (error) { this.toast((error as Error).message || 'PDF 导出失败'); }
    finally { this.busy = false; }
  }

  private async deleteResponse(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除这份回答', message: '删除后无法恢复。',
      buttons: [{ text: '取消', color: '#66758A' }, { text: '删除', color: '#D74747' }]
    });
    if (result.index !== 1) { return; }
    try {
      const next = this.responses.filter((response: FormResponse) => response.id !== this.selectedResponse.id);
      await StorageService.setValue('forms.responses', JSON.stringify(next));
      this.responses = next;
      this.mode = 'responses';
    } catch (error) { this.toast('删除失败，请重试'); }
  }

  private hasUnsavedChanges(): boolean {
    if (this.mode === 'edit') {
      const saved = this.forms.find((form: LocalForm) => form.id === this.draft.id);
      return saved ? JSON.stringify(saved) !== JSON.stringify(this.draft) :
        this.draft.title.length > 0 || this.draft.description.length > 0 || this.draft.fields.length > 0;
    }
    if (this.mode === 'field') {
      const saved = this.draft.fields.find((field: FormField) => field.id === this.field.id);
      return this.optionsText !== this.field.options.join('\n') || (saved ? JSON.stringify(saved) !== JSON.stringify(this.field) :
        this.field.type !== 'text' || this.field.label.length > 0 || this.field.description.length > 0 ||
        this.field.required || this.field.defaultValue.length > 0);
    }
    if (this.mode === 'fill') {
      return this.draft.fields.some((field: FormField) => {
        const answer = this.answer(field);
        return answer.attachments.length > 0 || answer.value !== field.defaultValue;
      });
    }
    return false;
  }

  private async goBack(): Promise<void> {
    if (this.busy) { this.toast('请等待当前操作完成'); return; }
    if (this.confirmingBack) { return; }
    if (['edit', 'fill', 'field'].includes(this.mode)) {
      try { await this.flushDraft(); } catch (_) { this.message = '草稿未能保存，请稍后再返回'; return; }
    }
    this.message = '';
    if (this.mode === 'list') { this.pathStack.pop(); }
    else if (this.mode === 'response') { this.mode = 'responses'; }
    else if (this.mode === 'edit') { this.mode = 'list'; }
    else { this.mode = 'edit'; }
  }

  @Builder
  private input(label: string, value: string, placeholder: string, change: (value: string) => void) {
    Column({ space: 8 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary'))
      TextInput({ text: value, placeholder: placeholder }).id('forms-input-' + label).height(48).borderRadius(13)
        .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onChange(change)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private listing() {
    Column({ space: 16 }) {
      Column({ space: 10 }) {
        Text('只在你的设备上').fontSize(12).fontColor($r('app.color.brand'))
        Text('让收集，变得井井有条').fontSize(23).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text('设计字段 · 本地填写 · 自由导出').fontSize(13).fontColor($r('app.color.text_secondary'))
      }.width('100%').padding(24).backgroundColor($r('app.color.surface')).borderRadius(24).alignItems(HorizontalAlign.Start)
      Search({ value: this.query, placeholder: '搜索本地表单' }).id('forms-search').height(48).backgroundColor($r('app.color.surface'))
        .onChange((value: string) => { this.query = value; })
      if (this.savedDraft) {
        Text('未完成：' + (this.savedDraft.schema.title || '未命名表单') + ' · ' + new Date(this.savedDraft.savedAt).toLocaleString()).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
        Row({ space: 10 }) {
          Button('继续草稿').id('forms-resume-draft').layoutWeight(1).onClick(() => this.resumeDraft())
          Button('清除草稿').layoutWeight(1).onClick(() => { this.discardDraft().catch(() => { this.message = '清除失败'; }); })
        }.width('100%')
      }
      Row({ space: 8 }) {
        Button('物品登记模板').fontSize(12).layoutWeight(1).onClick(() => this.useTemplate(0))
        Button('检查清单').fontSize(12).layoutWeight(1).onClick(() => this.useTemplate(1))
        Button('活动报名').fontSize(12).layoutWeight(1).onClick(() => this.useTemplate(2))
      }.width('100%')
      Button('＋ 新建表单').id('forms-create').height(46).width('100%').fontSize(14)
        .backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(() => this.createForm())
      if (!this.ready) { LoadingProgress().width(32).height(32).color($r('app.color.brand')) }
      else if (this.visibleForms().length === 0) {
        Column({ space: 12 }) {
          Text(this.forms.length ? '没有匹配的表单' : '从一张空白表单开始').fontSize(19)
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text('为报名、清单、调研或日常记录\n创建适合自己的信息结构').fontSize(13).lineHeight(22)
            .textAlign(TextAlign.Center).fontColor($r('app.color.text_secondary'))
        }.padding({ top: 42, bottom: 44 }).width('100%')
      }
      ForEach(this.visibleForms(), (form: LocalForm) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 14 }) {
            Text('≡').fontSize(28).fontColor($r('app.color.brand')).width(50).height(54)
              .textAlign(TextAlign.Center).backgroundColor($r('app.color.brand_soft')).borderRadius(16)
            Column({ space: 8 }) {
              Text(form.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(1)
              Text(`${form.fields.length} 个字段 · ${this.formResponses(form.id).length} 份回答`).fontSize(12).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('›').fontSize(26).fontColor($r('app.color.text_secondary'))
          }.width('100%')
        }.id('forms-card-' + form.id).accessibilityText(form.title)
          .padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20).onClick(() => this.open(form))
      }, (form: LocalForm) => `${form.id}_${form.updatedAt}_${this.formResponses(form.id).length}`)
    }.width('100%')
  }

  @Builder
  private schemaEditor() {
    Column({ space: 18 }) {
      Text('修改会自动保存为本地草稿；长按字段可拖动排序。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
      Button('复制为新表单').id('forms-duplicate').onClick(() => this.duplicateForm())
      Column({ space: 18 }) {
        this.input('表单标题 *', this.draft.title, '给表单起个名字', (value: string) => { this.draft.title = value; })
        TextArea({ text: this.draft.description, placeholder: '表单说明（可选）' }).attributeModifier(this.descriptionScroll).height(90)
          .backgroundColor($r('app.color.soft_surface')).borderRadius(13)
          .onChange((value: string) => { this.draft.description = value; })
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
      Row() {
        Text(`字段 · ${this.draft.fields.length}`).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button('＋ 添加字段').id('forms-add-field').height(36).fontSize(13).fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_soft')).onClick(() => this.editField())
      }.width('100%')
      if (this.draft.fields.length === 0) {
        Text('添加文字、选择、日期等字段\n可用上下箭头调整显示顺序').fontSize(13).lineHeight(22).textAlign(TextAlign.Center)
          .fontColor($r('app.color.text_secondary')).width('100%').padding(28)
      }
      ForEach(this.draft.fields, (field: FormField, index: number) => {
        Column({ space: 14 }) {
          Row({ space: 10 }) {
            Text(`${index + 1}` ).fontSize(13).fontColor($r('app.color.brand')).width(28).height(28)
              .textAlign(TextAlign.Center).backgroundColor($r('app.color.brand_soft')).borderRadius(8)
            Column({ space: 6 }) {
              Text(`${field.label}${field.required ? ' *' : ''}`).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text(fieldTypeName(field.type)).fontSize(11).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button('编辑').fontSize(12).height(32).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.brand')).onClick(() => this.editField(field))
          }.width('100%')
          Row({ space: 8 }) {
            Button('↑ 上移').fontSize(12).height(32).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.text_secondary')).enabled(index > 0).onClick(() => this.moveField(index, -1))
            Button('↓ 下移').fontSize(12).height(32).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.text_secondary')).enabled(index < this.draft.fields.length - 1).onClick(() => this.moveField(index, 1))
            Button('移除').fontSize(12).height(32).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
              .fontColor($r('app.color.error')).onClick(() => { this.draft.fields = this.draft.fields.filter((entry: FormField) => entry.id !== field.id); })
          }.width('100%')
        }.draggable(true).onDragStart(() => { this.dragFieldId = field.id; }).onDrop(() => this.dropField(field.id))
          .padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
      }, (field: FormField, fieldIndex: number) => field.id + '_' + fieldIndex.toString())
      Row({ space: 10 }) {
        Button('实时预览').id('forms-preview').height(46).layoutWeight(1).fontColor($r('app.color.brand')).backgroundColor($r('app.color.surface'))
          .enabled(!this.busy).onClick(() => this.startFill(true))
        Button('开始填写').id('forms-fill').height(46).layoutWeight(1).fontColor($r('app.color.brand')).backgroundColor($r('app.color.surface'))
          .enabled(!this.busy).onClick(() => this.startFill(false))
      }.width('100%')
      Button('保存表单').id('forms-save-schema').height(50).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.busy)
        .onClick(() => this.saveSchema())
      this.exportSection()
      if (this.forms.some((form: LocalForm) => form.id === this.draft.id)) {
        Button('删除表单').id('forms-delete').height(44).width('100%').backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.error')).enabled(!this.busy).onClick(() => this.deleteForm())
      }
    }.width('100%')
  }

  @Builder
  private exportSection() {
    Column({ space: 14 }) {
      Row() {
        Text('本地数据').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button(`回答 ${this.formResponses(this.draft.id).length} ›`).id('forms-responses').fontSize(12).height(34).fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_soft')).onClick(() => { this.mode = 'responses'; })
      }.width('100%')
      Row({ space: 8 }) {
        Button('JSON Schema').fontSize(12).height(40).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
          .fontColor($r('app.color.brand')).enabled(!this.busy).onClick(() => this.exportData('schema'))
        Button('CSV 模板').fontSize(12).height(40).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
          .fontColor($r('app.color.brand')).enabled(!this.busy).onClick(() => this.exportData('template'))
      }.width('100%')
      Row({ space: 8 }) {
        Button('回答 CSV').fontSize(12).height(40).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
          .fontColor($r('app.color.brand')).enabled(!this.busy).onClick(() => this.exportData('csv'))
        Button('回答 JSON').fontSize(12).height(40).layoutWeight(1).backgroundColor($r('app.color.soft_surface'))
          .fontColor($r('app.color.brand')).enabled(!this.busy).onClick(() => this.exportData('json'))
      }.width('100%')
      Button('PDF 空白 / 打印模板').id('forms-export-template-pdf').fontSize(13).height(42).width('100%').backgroundColor($r('app.color.soft_surface'))
        .fontColor($r('app.color.brand')).enabled(!this.busy).onClick(() => this.exportPdf())
      Text('表单与回答仅保存在本机。导出的回答包含附件信息，附件文件可在回答详情中单独导出。')
        .fontSize(11).lineHeight(18).fontColor($r('app.color.text_secondary'))
    }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private fieldEditor() {
    Column({ space: 18 }) {
      Column({ space: 18 }) {
        this.input('字段名称 *', this.field.label, '例如：姓名', (value: string) => { this.field.label = value; })
        Text('字段类型').fontSize(13).fontColor($r('app.color.text_secondary'))
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
          ForEach(FIELD_TYPES, (type: string, index: number) => {
            Button(FIELD_NAMES[index], { type: ButtonType.Normal }).id('forms-type-' + type).height(36).fontSize(12).borderRadius(10)
              .backgroundColor(this.field.type === type ? $r('app.color.brand') : $r('app.color.soft_surface'))
              .fontColor(this.field.type === type ? $r('app.color.inverse_text') : $r('app.color.text_secondary'))
              .onClick(() => { this.field.type = type; this.field.defaultValue = ''; })
          })
        }.width('100%')
        this.input('字段说明', this.field.description, '帮助填写者理解这个字段', (value: string) => { this.field.description = value; })
        Row() {
          Text('必填字段').fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.field.required }).id('forms-field-required').selectedColor($r('app.color.brand'))
            .onChange((value: boolean) => { this.field.required = value; })
        }.width('100%')
        if (['radio', 'checkbox', 'select'].includes(this.field.type)) {
          Text('选项 · 每行一个，至少两个').fontSize(13).fontColor($r('app.color.text_secondary'))
          TextArea({ text: this.optionsText, placeholder: '选项一\n选项二' }).id('forms-field-options').attributeModifier(this.optionsScroll).height(140).borderRadius(13)
            .backgroundColor($r('app.color.soft_surface')).onChange((value: string) => { this.optionsText = value; })
        }
        if (this.field.type !== 'attachment') {
          this.input('默认值（可选）', this.field.defaultValue,
            this.field.type === 'checkbox' ? '多个选项使用 | 分隔' : this.field.type === 'rating' ? '1–5' : this.field.type === 'date' ? 'YYYY-MM-DD' : '初始填写内容',
            (value: string) => { this.field.defaultValue = value; })
        }
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
      Button('完成字段').id('forms-field-save').height(50).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(() => this.saveField())
    }.width('100%')
  }

  @Builder
  private renderedField(field: FormField) {
    Column({ space: 12 }) {
      Text(`${field.label}${field.required ? ' *' : ''}`).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      if (field.description) { Text(field.description).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary')) }
      if (field.type === 'textarea') {
        TextArea({ text: this.answer(field).value, placeholder: '请填写' }).id('forms-answer-' + field.label).attributeModifier(this.answerScroll(field.id)).height(110).borderRadius(13)
          .backgroundColor($r('app.color.soft_surface')).onChange((value: string) => this.setAnswer(field, value))
      } else if (field.type === 'radio' || field.type === 'checkbox') {
        ForEach(field.options, (option: string) => {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 10 }) {
              Text(field.type === 'checkbox' ? (this.isChosen(field, option) ? '☑' : '□') : (this.answer(field).value === option ? '●' : '○'))
                .fontSize(20).fontColor($r('app.color.brand'))
              Text(option).fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1).textAlign(TextAlign.Start)
            }.width('100%')
          }.id('forms-choice-' + field.label + '-' + option).padding(13).width('100%').backgroundColor($r('app.color.soft_surface')).borderRadius(12)
            .onClick(() => { if (field.type === 'checkbox') { this.toggleChoice(field, option); } else { this.setAnswer(field, option); } })
        })
      } else if (field.type === 'select') {
        Select(field.options.map((option: string): SelectOption => { return { value: option }; }))
          .value(this.answer(field).value || '请选择').width('100%').height(46).backgroundColor($r('app.color.soft_surface'))
          .onSelect((index: number) => { this.setAnswer(field, field.options[index]); })
      } else if (field.type === 'rating') {
        Row({ space: 8 }) {
          ForEach([1, 2, 3, 4, 5], (rating: number) => {
            Button('★', { type: ButtonType.Normal }).width(42).height(44).fontSize(27).borderRadius(12)
              .fontColor(Number(this.answer(field).value) >= rating ? $r('app.color.brand') : $r('app.color.text_secondary'))
              .backgroundColor($r('app.color.soft_surface')).accessibilityText(`${rating} 分`)
              .onClick(() => this.setAnswer(field, `${rating}`))
          })
        }
      } else if (field.type === 'attachment') {
        Button('＋ 选择本地附件').height(42).fontSize(13).backgroundColor($r('app.color.brand_soft'))
          .fontColor($r('app.color.brand')).enabled(!this.busy && this.mode !== 'preview').onClick(() => this.answerAttachment(field))
        ForEach(this.answer(field).attachments, (attachment: LocalAttachment) => {
          Row({ space: 8 }) {
            Text(attachment.name).fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1)
            Button('移除').fontSize(11).height(30).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.error'))
              .onClick(() => {
                this.answers = this.answers.map((answer: FieldAnswer) => {
                  if (answer.fieldId === field.id) { answer.attachments = answer.attachments.filter((entry: LocalAttachment) => entry.id !== attachment.id); }
                  return answer;
                });
              })
          }.width('100%')
        }, (attachment: LocalAttachment) => attachment.id)
      } else if (field.type === 'date') {
        Row({ space: 8 }) {
          TextInput({ text: this.answer(field).value, placeholder: 'YYYY-MM-DD' }).id('forms-answer-' + field.label).height(46).layoutWeight(1)
            .backgroundColor($r('app.color.soft_surface')).onChange((value: string) => this.setAnswer(field, value))
          Button('选择').height(42).fontSize(12).backgroundColor($r('app.color.brand_soft'))
            .fontColor($r('app.color.brand')).onClick(() => this.pickDate(field))
        }.width('100%')
      } else {
        TextInput({ text: this.answer(field).value, placeholder: field.type === 'number' ? '请输入数字' : '请填写' }).id('forms-answer-' + field.label)
          .height(46).type(field.type === 'number' ? InputType.Number : InputType.Normal)
          .backgroundColor($r('app.color.soft_surface')).borderRadius(13).onChange((value: string) => this.setAnswer(field, value))
      }
    }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(20).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private fillForm() {
    Column({ space: 16 }) {
      Column({ space: 10 }) {
        if (this.mode === 'preview') { Text('预览模式 · 填写内容不会保存').fontSize(12).fontColor($r('app.color.brand')) }
        Text(this.draft.title || '未命名表单').fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        if (this.draft.description) { Text(this.draft.description).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')) }
        Text('* 为必填项').fontSize(11).fontColor($r('app.color.text_secondary'))
      }.width('100%').padding(24).backgroundColor($r('app.color.surface')).borderRadius(24).alignItems(HorizontalAlign.Start)
      ForEach(this.draft.fields, (field: FormField) => { this.renderedField(field) }, (field: FormField) => field.id)
      if (this.mode === 'fill') {
        Button(this.busy ? '保存中…' : '保存本地回答').id('forms-submit').height(50).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text'))
          .enabled(!this.busy).onClick(() => this.submit())
      }
    }.width('100%')
  }

  @Builder
  private responseList() {
    Column({ space: 16 }) {
      Text(this.draft.title).fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text(`${this.formResponses(this.draft.id).length} 份本地回答`).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      this.exportSection()
      if (!this.formResponses(this.draft.id).length) {
        Text('还没有回答，返回后点击「开始填写」').fontSize(13).fontColor($r('app.color.text_secondary')).padding(30)
      }
      ForEach(this.formResponses(this.draft.id), (response: FormResponse) => {
        Button({ type: ButtonType.Normal }) {
          Row() {
            Column({ space: 8 }) {
              Text(response.submittedAt).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text(`${response.answers.length} 个字段 · 查看回答`).fontSize(12).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('›').fontSize(26).fontColor($r('app.color.text_secondary'))
          }.width('100%')
        }.id('forms-response-card-' + response.id).padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
          .onClick(() => { this.selectedResponse = response; this.mode = 'response'; })
      }, (response: FormResponse) => response.id)
    }.width('100%')
  }

  private async exportAnswerAttachment(attachment: LocalAttachment): Promise<void> {
    try {
      if (await InventoryFiles.exportAttachment(this.context(), attachment)) { this.toast('附件已导出'); }
    } catch (error) { this.toast('附件导出失败'); }
  }

  @Builder
  private responseDetail() {
    Column({ space: 16 }) {
      Text(this.selectedResponse.formTitle).id('forms-response-title').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text(this.selectedResponse.submittedAt).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
      ForEach(this.selectedResponse.answers, (answer: FieldAnswer) => {
        Column({ space: 12 }) {
          Text(answer.label).fontSize(13).fontColor($r('app.color.text_secondary'))
          if (answer.type === 'attachment') {
            if (!answer.attachments.length) { Text('未填写').fontSize(15).fontColor($r('app.color.text_primary')) }
            ForEach(answer.attachments, (attachment: LocalAttachment) => {
              Button(attachment.name).fontSize(13).height(42).fontColor($r('app.color.brand'))
                .backgroundColor($r('app.color.brand_soft')).onClick(() => this.exportAnswerAttachment(attachment))
            }, (attachment: LocalAttachment) => attachment.id)
          } else {
            Text(answer.value || '未填写').id('forms-value-' + answer.label).fontSize(15).lineHeight(24).fontColor($r('app.color.text_primary')).copyOption(CopyOptions.LocalDevice)
          }
        }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(20).alignItems(HorizontalAlign.Start)
      }, (answer: FieldAnswer) => answer.fieldId)
      Button(this.busy ? '正在生成 PDF…' : '导出这份回答 PDF').id('forms-export-response-pdf').height(48).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text'))
        .enabled(!this.busy).onClick(() => this.exportPdf(this.selectedResponse))
      Button('删除这份回答').id('forms-response-delete').height(46).width('100%').backgroundColor($r('app.color.surface')).fontColor($r('app.color.error')).enabled(!this.busy)
        .onClick(() => this.deleteResponse())
    }.width('100%')
  }

  private tutorialArticleId(): string {
    if (this.mode === 'field') { return 'form-fields'; }
    if (this.mode === 'fill' || this.mode === 'preview' || this.mode === 'responses' || this.mode === 'response') {
      return 'form-fill';
    }
    return 'forms';
  }

  @Builder
  private pageTitleBar() {
    LumiBackHeader({ title: this.mode === 'list' ? '本地表单' : this.mode === 'field' ? '编辑字段' : this.mode === 'fill' ? '填写表单' :
      this.mode === 'preview' ? '实时预览' : this.mode === 'responses' || this.mode === 'response' ? '本地回答' : '设计表单',
      onBack: () => { this.goBack(); }, showTutorial: true, tutorialEnabled: !this.busy,
      onTutorial: () => { LumiHelpNavigation.open(this.pathStack, this.tutorialArticleId()); } })
  }

  private modeTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 220, curve: curves.cubicBezierCurve(0.23, 1, 0.32, 1) }),
      TransitionEffect.IDENTITY
    );
  }

  build() {
    NavDestination() {
      Scroll(this.pageScroller) {
        Column() {
          if (this.mode === 'list') { Column() { this.listing() }.width('100%').transition(this.modeTransition()) }
          else if (this.mode === 'edit') {
            Column() {
              ForEach([this.draft.id], (schemaId: string) => { this.schemaEditor() }, (schemaId: string) => schemaId)
            }.width('100%').transition(this.modeTransition())
          }
          else if (this.mode === 'field') { Column() { this.fieldEditor() }.width('100%').transition(this.modeTransition()) }
          else if (this.mode === 'fill' || this.mode === 'preview') { Column() { this.fillForm() }.width('100%').transition(this.modeTransition()) }
          else if (this.mode === 'responses') { Column() { this.responseList() }.width('100%').transition(this.modeTransition()) }
          else { Column() { this.responseDetail() }.width('100%').transition(this.modeTransition()) }
          if (this.message) { Text(this.message).id('forms-validation-message').fontSize(13).fontColor($r('app.color.error')).width('100%').padding({ top: 14, bottom: 14 }) }
        }.id('forms-page-' + this.mode).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 36 + this.bottomInset })
      }.width('100%').height('100%').contentStartOffset(56)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]).scrollBar(BarState.Off).align(Alignment.Top)
    }
    .hideBackButton(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .title({ builder: () => { this.pageTitleBar(); }, height: 56 }, {
      barStyle: BarStyle.STACK,
      scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as LumiRecordRouteParam;
      if (param?.recordId) { this.recordId = param.recordId; const selected = this.forms.find((form: LocalForm) => form.id === this.recordId); if (selected) { this.open(selected); } }
    })
    .onBackPressed(() => { this.goBack(); return true; })
    .backgroundColor($r('app.color.background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
