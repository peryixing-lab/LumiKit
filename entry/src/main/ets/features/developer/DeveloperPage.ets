import { TextAreaPageScroll } from '../../core/TextAreaPageScroll';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { LumiHelpNavigation } from '../help/HelpNavigation';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { StorageService } from '../../core/StorageService';
import {
  ColorConversion, DiffLine, MarkdownBlock, MarkdownInline, TimestampConversion,
  compareLines, convertColor, convertTimestamp, convertUrl, decodeBase64, encodeBase64,
  formatJson, parseMarkdown, suggestTool, validateJson
} from './DeveloperUtils';
import { DeveloperRuntime } from './DeveloperRuntime';

export class DeveloperRouteParam {
  toolId: string = 'json';
}

@Builder
export function developerBuilder() {
  DeveloperPage()
}

class LumiDeveloperDraft {
  input: string = '';
  otherInput: string = '';
  mode: number = 0;
  regexPattern: string = '';
  regexFlags: string = '';
  uuidCount: string = '1';
}

class DeveloperTool {
  id: string;
  title: string;
  description: string;
  example: string;
  placeholder: string;

  constructor(id: string, title: string, description: string, example: string, placeholder: string) {
    this.id = id;
    this.title = title;
    this.description = description;
    this.example = example;
    this.placeholder = placeholder;
  }
}

const TOOLS: DeveloperTool[] = [
  new DeveloperTool('json', 'JSON 格式化', '让结构清晰，让每个细节井然有序。',
    '{"name":"LumiKit","中文":"集萤","version":1,"tools":["JSON","Base64"]}', '在这里输入或粘贴 JSON…'),
  new DeveloperTool('base64', 'Base64 编解码', '在文本与编码之间，轻松往返。', '你好，LumiKit 👋', '输入需要编码的文本，或 Base64 字符串…'),
  new DeveloperTool('url', 'URL 编解码', '安全处理网址参数中的特殊字符。', '你好 LumiKit & blue=white', '输入文本或百分号编码…'),
  new DeveloperTool('timestamp', '时间戳转换', '把一串数字，还原为清晰的时刻。', '2026-10-15 12:00:00+08:00',
    '秒 / 毫秒时间戳，或 2026-10-15 12:00:00…'),
  new DeveloperTool('hash', 'SHA-256 哈希', '在本机生成文本的 SHA-256 摘要。', 'LumiKit', '输入要计算哈希的文本（可为空）…'),
  new DeveloperTool('uuid', 'UUID 生成器', '为新的想法，创建一个独一无二的标识。', '', ''),
  new DeveloperTool('color', '颜色转换', '让灵感在 HEX、RGB 与 HSL 之间流动。', '#2878F0', '例如 #2878F0、rgb(40, 120, 240)…'),
  new DeveloperTool('diff', '文本对比', '从每一行中，发现细微的变化。', 'LumiKit\n本地优先\n让日常轻一点', '输入原始文本…'),
  new DeveloperTool('regex', '正则测试', '即时验证表达式，查看匹配与捕获分组。', 'hello@lumikit.app\nteam@example.com\n这不是邮箱',
    '输入用于匹配的测试文本…'),
  new DeveloperTool('markdown', 'Markdown 预览', '专注文字，也看见它呈现的模样。',
    '# 你好，集萤\n\n让每个 **日常灵感** 都有归处。\n\n## 我们相信\n\n- 本地优先\n- 轻巧实用\n- 认真对待隐私\n\n> 聚微光，成日常。\n\n```typescript\nconst hello = "LumiKit";\n```',
    '输入 Markdown，预览会实时更新…')
];

function findTool(id: string): DeveloperTool {
  return TOOLS.find((tool: DeveloperTool) => tool.id === id) || TOOLS[0];
}

@Component
export struct DeveloperPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State private activeToolId: string = 'json';
  @State @Watch('scheduleDraft') private input: string = '';
  @State @Watch('scheduleDraft') private otherInput: string = '';
  @State private output: string = '';
  @State private error: string = '';
  @State private status: string = '';
  @State @Watch('scheduleDraft') private mode: number = 0;
  @State @Watch('scheduleDraft') private regexPattern: string = '[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}';
  @State @Watch('scheduleDraft') private regexFlags: string = 'g';
  @State @Watch('scheduleDraft') private uuidCount: string = '1';
  @State private isBusy: boolean = false;
  @State private recordUsage: boolean = false;
  @State private suggestion: string = '';
  @State private colorPreview: string = '';
  @State private differences: DiffLine[] = [];
  @State private markdown: MarkdownBlock[] = [];
  @State private draftEnabled: boolean = false;
  private restoringDraft: boolean = false;
  private draftTimer: number = -1;
  private toolId: string = 'json';
  private generation: number = 0;
  private pathStack: NavPathStack = new NavPathStack();
  private readonly pageScroller: Scroller = new Scroller();
  private readonly primaryInputScroll: TextAreaPageScroll = new TextAreaPageScroll();
  private readonly secondaryInputScroll: TextAreaPageScroll = new TextAreaPageScroll();

  aboutToAppear(): void {
    this.activeToolId = findTool(this.toolId).id;
  }

  aboutToDisappear(): void {
    this.persistDraft().catch(() => {});
    this.generation++;
  }

  private selectTool(id: string, preserveInput: boolean = false): void {
    this.persistDraft().catch(() => {});
    this.generation++;
    this.activeToolId = findTool(id).id;
    this.mode = 0;
    this.output = '';
    this.error = '';
    this.status = '';
    this.differences = [];
    this.colorPreview = '';
    this.suggestion = '';
    this.isBusy = false;
    if (!preserveInput) {
      this.input = '';
      this.otherInput = '';
    }
    this.updateMarkdown();
    this.loadDraft().catch(() => { this.status = '草稿读取失败'; });
  }

  private scheduleDraft(): void {
    if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); this.draftTimer = -1; }
    if (!this.draftEnabled || this.restoringDraft) { return; }
    this.draftTimer = setTimeout(() => { this.persistDraft().catch(() => { this.status = '草稿保存失败，请复制重要内容'; }); }, 350);
  }
  private async persistDraft(): Promise<void> {
    if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); this.draftTimer = -1; }
    if (!this.draftEnabled) { return; }
    const saved = new LumiDeveloperDraft(); saved.input = this.input; saved.otherInput = this.otherInput;
    saved.mode = this.mode; saved.regexPattern = this.regexPattern; saved.regexFlags = this.regexFlags; saved.uuidCount = this.uuidCount;
    await StorageService.setValue('developer.draft.' + this.activeToolId, JSON.stringify(saved));
  }
  private async loadDraft(): Promise<void> {
    const id = this.activeToolId; const generation = this.generation;
    this.restoringDraft = true; if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); this.draftTimer = -1; }
    const enabled = await StorageService.getSetting('developerDraftsEnabled', 'false') === 'true';
    const saved = JSON.parse(await StorageService.getValue('developer.draft.' + id, 'null')) as LumiDeveloperDraft;
    this.restoringDraft = false;
    if (id !== this.activeToolId || generation !== this.generation) { this.scheduleDraft(); return; }
    this.draftEnabled = enabled;
    if (enabled && saved && typeof saved.input === 'string' && typeof saved.otherInput === 'string' &&
      saved.input.length <= 200000 && saved.otherInput.length <= 200000) {
      this.input = saved.input; this.otherInput = saved.otherInput; this.mode = saved.mode;
      this.regexPattern = saved.regexPattern; this.regexFlags = saved.regexFlags; this.uuidCount = saved.uuidCount;
      this.updateMarkdown(); this.status = '已恢复本地草稿';
    }
  }
  private async setDraftEnabled(enabled: boolean): Promise<void> {
    try {
      await StorageService.setSetting('developerDraftsEnabled', enabled.toString()); this.draftEnabled = enabled;
      if (enabled) { await this.persistDraft(); }
      else {
        if (this.draftTimer >= 0) { clearTimeout(this.draftTimer); this.draftTimer = -1; }
        for (const tool of TOOLS) { await StorageService.setValue('developer.draft.' + tool.id, 'null'); }
      }
    } catch (_) { this.status = '草稿设置未能保存'; }
  }
  private async clearDraft(): Promise<void> {
    this.changedInput(''); this.otherInput = ''; this.mode = 0; this.regexPattern = '[\\w.+-]+@[\\w.-]+\\.[A-Za-z]{2,}'; this.regexFlags = 'g'; this.uuidCount = '1'; await this.persistDraft(); this.status = '本工具的草稿已清空';
  }

  private changedInput(value: string, secondary: boolean = false): void {
    this.generation++;
    this.isBusy = false;
    if (secondary) {
      this.otherInput = value;
    } else {
      this.input = value;
    }
    this.output = '';
    this.error = '';
    this.status = '';
    this.colorPreview = '';
    this.differences = [];
    this.suggestion = '';
    this.updateMarkdown();
  }

  private updateMarkdown(): void {
    if (this.activeToolId === 'markdown') {
      this.markdown = parseMarkdown(this.input);
    }
  }

  private loadExample(): void {
    const tool: DeveloperTool = findTool(this.activeToolId);
    this.mode = 0;
    this.changedInput(tool.example);
    if (this.activeToolId === 'diff') {
      this.otherInput = 'LumiKit\n本地优先\n蓝白之间，聚起微光\n让日常轻一点';
    }
  }

  private async paste(result: PasteButtonOnClickResult, secondary: boolean = false): Promise<void> {
    if (result !== PasteButtonOnClickResult.SUCCESS) {
      this.error = '未能获得本次粘贴授权，请重试或使用输入框的系统粘贴菜单。';
      return;
    }
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text: string = data.getPrimaryText();
      if (!text) {
        this.status = '剪贴板中没有可用的文本。';
        return;
      }
      if (text.length > 200000 || (this.activeToolId === 'markdown' && text.length > 30000)) {
        this.error = this.activeToolId === 'markdown' ? 'Markdown 最多支持 30,000 个字符。' :
          '文本最多支持 200,000 个字符，请缩小内容后粘贴。';
        return;
      }
      this.changedInput(text, secondary);
      if (!secondary) {
        const detected: string = suggestTool(text);
        this.suggestion = detected !== this.activeToolId ? detected : '';
      }
      this.status = '已粘贴，请确认内容后操作。';
    } catch (error) {
      this.error = '无法读取剪贴板，请使用输入框的系统粘贴菜单。';
    }
  }

  private async copy(): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.output));
      this.status = '已复制结果。';
    } catch (error) {
      this.error = '复制失败，请长按结果选择文本后复制。';
    }
  }

  private modes(): string[] {
    if (this.activeToolId === 'json') {
      return ['格式化', '压缩', '校验'];
    }
    if (this.activeToolId === 'base64' || this.activeToolId === 'url') {
      return ['编码', '解码'];
    }
    if (this.activeToolId === 'timestamp') {
      return ['自动识别', '秒', '毫秒'];
    }
    return [];
  }

  private actionTitle(): string {
    if (this.activeToolId === 'json') {
      return ['格式化 JSON', '压缩 JSON', '校验 JSON'][this.mode];
    }
    if (this.activeToolId === 'base64' || this.activeToolId === 'url') {
      return this.mode === 0 ? '开始编码' : '开始解码';
    }
    if (this.activeToolId === 'timestamp' || this.activeToolId === 'color') {
      return '转换';
    }
    if (this.activeToolId === 'hash') {
      return '计算 SHA-256';
    }
    if (this.activeToolId === 'uuid') {
      return '生成 UUID v4';
    }
    return this.activeToolId === 'regex' ? '测试表达式' : '开始对比';
  }

  private note(): string {
    if (this.activeToolId === 'json') {
      return '保留原始数字精度 · 2 空格缩进 · 支持所有合法 JSON 值';
    }
    if (this.activeToolId === 'base64') {
      return '使用标准 Base64 与 UTF-8；仅解码有效的 UTF-8 文本。';
    }
    if (this.activeToolId === 'url') {
      return '使用 encodeURIComponent / decodeURIComponent。+ 保持为 +，不作表单空格转换。';
    }
    if (this.activeToolId === 'timestamp') {
      return '自动识别：10 位以内为秒，其余为毫秒。无时区日期按设备本地时区解释。';
    }
    if (this.activeToolId === 'hash') {
      return '按 UTF-8 字节计算。空格与换行也参与计算，支持空文本。';
    }
    if (this.activeToolId === 'diff') {
      return '按行对比，保留空格差异。每侧最多 300 行，总计 40,000 字符。';
    }
    if (this.activeToolId === 'regex') {
      return '无需输入 / 分隔符。支持 g i m s u；后台执行，超时自动停止。';
    }
    if (this.activeToolId === 'markdown') {
      return '支持标题、强调、列表、引用和代码块。链接显示文字，HTML 作为纯文本展示。';
    }
    return this.activeToolId === 'uuid' ? '使用系统随机 UUID v4，每次可生成 1–100 个。' :
      '支持不透明 HEX / RGB / HSL；HSL 转 RGB 按最近整数取值。';
  }

  private async execute(): Promise<void> {
    if (this.isBusy) {
      return;
    }
    this.error = '';
    this.status = '';
    this.output = '';
    this.differences = [];
    this.colorPreview = '';
    const currentGeneration: number = ++this.generation;
    this.isBusy = true;
    try {
      let result: string = '';
      if (this.input.length > 200000) {
        throw new Error('输入最多支持 200,000 个字符。');
      }
      if (this.activeToolId === 'json') {
        if (this.mode === 2) {
          validateJson(this.input);
          result = '✓ JSON 校验通过\n\n语法正确，可以进行格式化或压缩。';
        } else {
          result = formatJson(this.input, this.mode === 1);
        }
      } else if (this.activeToolId === 'base64') {
        result = this.mode === 0 ? encodeBase64(this.input) : decodeBase64(this.input);
      } else if (this.activeToolId === 'url') {
        result = convertUrl(this.input, this.mode === 1);
      } else if (this.activeToolId === 'timestamp') {
        const timestamp: TimestampConversion = convertTimestamp(this.input, ['auto', 's', 'ms'][this.mode]);
        result = '秒时间戳\n' + timestamp.seconds + '\n\n毫秒时间戳\n' + timestamp.milliseconds +
          '\n\n本地时间\n' + timestamp.local + '\n\nUTC\n' + timestamp.utc;
      } else if (this.activeToolId === 'hash') {
        result = await DeveloperRuntime.sha256(this.input);
      } else if (this.activeToolId === 'uuid') {
        result = DeveloperRuntime.uuids(Number(this.uuidCount));
      } else if (this.activeToolId === 'color') {
        const color: ColorConversion = convertColor(this.input);
        this.colorPreview = color.hex;
        result = color.hex + '\n' + color.rgb + '\n' + color.hsl;
      } else if (this.activeToolId === 'diff') {
        this.differences = compareLines(this.input, this.otherInput);
        result = this.differences.map((line: DiffLine) =>
          (line.kind === 'add' ? '+ ' : line.kind === 'remove' ? '- ' : '  ') + line.text).join('\n');
      } else if (this.activeToolId === 'regex') {
        result = await DeveloperRuntime.regex(this.regexPattern, this.regexFlags, this.input);
      }
      if (currentGeneration !== this.generation) {
        return;
      }
      this.output = result;
      this.status = result.length === 0 ? '处理完成，结果为空文本。' : '已在本地完成处理。';
      if (this.recordUsage) {
        try {
          await StorageService.addHistory(this.activeToolId, findTool(this.activeToolId).title,
            '本地处理完成 · 未保存输入与结果正文');
        } catch (historyError) {
          this.status = '处理完成，工具使用记录未能保存。';
        }
      }
    } catch (caught) {
      if (currentGeneration !== this.generation) {
        return;
      }
      const message: string = (caught as Error).message || '';
      this.error = this.activeToolId === 'regex' && ((caught as BusinessError).code === 10200058 ||
        /timeout|time out|exceed|任务.*超时/i.test(message)) ?
        '表达式运行超时，请简化表达式或缩短测试文本后重试。' : (message || '处理失败，请检查输入后重试。');
    } finally {
      if (currentGeneration === this.generation) {
        this.isBusy = false;
      }
    }
  }

  @Builder
  private modeSelector() {
    Row({ space: 4 }) {
      ForEach(this.modes(), (label: string, index: number) => {
        Button(label, { type: ButtonType.Normal })
          .fontSize(14).fontWeight(index === this.mode ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(index === this.mode ? $r('app.color.brand') : $r('app.color.text_secondary'))
          .backgroundColor(index === this.mode ? $r('app.color.surface') : Color.Transparent)
          .borderRadius(10).height(40).layoutWeight(1)
          .onClick(() => {
            this.mode = index;
            this.generation++;
            this.isBusy = false;
            this.output = '';
            this.error = '';
          })
      }, (label: string) => label)
    }
    .padding(4).width('100%').borderRadius(14).backgroundColor($r('app.color.soft_surface'))
  }

  @Builder
  private inputPanel(label: string, secondary: boolean = false) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        PasteButton({ text: PasteDescription.PASTE, buttonType: ButtonType.Normal })
          .fontSize(14).fontColor($r('app.color.brand')).backgroundColor($r('app.color.brand_soft'))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 }).borderRadius(9)
          .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => { this.paste(result, secondary); })
        Button('清空', { type: ButtonType.Normal }).fontSize(13).fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent).padding({ left: 8, right: 0 }).height(32)
          .onClick(() => this.changedInput('', secondary))
      }.width('100%')
      TextArea({ text: secondary ? this.otherInput : this.input, placeholder: secondary ? '输入修改后的文本…' :
        findTool(this.activeToolId).placeholder })
        .id(secondary ? 'dev-input-secondary' : 'dev-input')
        .attributeModifier(secondary ? this.secondaryInputScroll : this.primaryInputScroll).fontSize(14).fontFamily('monospace').fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary')).backgroundColor($r('app.color.soft_surface'))
        .borderRadius(12).padding(14).height(this.activeToolId === 'diff' ? 160 : 210)
        .maxLength(this.activeToolId === 'markdown' ? 30000 : 200000)
        .onChange((value: string) => this.changedInput(value, secondary))
      Row() {
        Text((secondary ? this.otherInput.length : this.input.length) + ' 字符').fontSize(11)
          .fontColor($r('app.color.text_secondary')).layoutWeight(1)
        if (!secondary) {
          Button('填入示例', { type: ButtonType.Normal }).fontSize(12).fontColor($r('app.color.brand'))
            .backgroundColor(Color.Transparent).padding(0).height(28).onClick(() => this.loadExample())
        }
      }.width('100%')
    }
    .padding(18).width('100%').borderRadius(20).backgroundColor($r('app.color.surface'))
  }

  @Builder
  private regexOptions() {
    Column({ space: 12 }) {
      Text('表达式').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
      TextInput({ text: this.regexPattern, placeholder: '例如 \\d+' })
        .fontSize(14).fontFamily('monospace').height(48).borderRadius(10)
        .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).maxLength(500)
        .onChange((value: string) => { this.regexPattern = value; this.changedInput(this.input); })
      Row({ space: 12 }) {
        Text('匹配标志').fontSize(13).fontColor($r('app.color.text_secondary'))
        TextInput({ text: this.regexFlags, placeholder: 'gimsu' }).height(42).layoutWeight(1).fontSize(14)
          .fontFamily('monospace').fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.soft_surface')).maxLength(5)
          .onChange((value: string) => { this.regexFlags = value; this.changedInput(this.input); })
      }.width('100%')
    }.width('100%').padding(18).borderRadius(20).backgroundColor($r('app.color.surface'))
  }

  @Builder
  private uuidOptions() {
    Column({ space: 18 }) {
      Text('一份新的唯一标识').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        .width('100%')
      Row({ space: 12 }) {
        Text('生成数量').fontSize(14).fontColor($r('app.color.text_secondary')).layoutWeight(1)
        TextInput({ text: this.uuidCount, placeholder: '1–100' }).width(120).height(48).type(InputType.Number)
          .fontSize(18).fontColor($r('app.color.brand')).backgroundColor($r('app.color.soft_surface')).textAlign(TextAlign.Center)
          .maxLength(3).onChange((value: string) => { this.uuidCount = value; this.error = ''; })
      }.width('100%')
      Row({ space: 8 }) {
        ForEach(['1', '5', '10', '20'], (count: string) => {
          Button(count + ' 个', { type: ButtonType.Normal }).fontSize(13).height(36).layoutWeight(1).borderRadius(10)
            .backgroundColor(this.uuidCount === count ? $r('app.color.brand_soft') : $r('app.color.soft_surface'))
            .fontColor(this.uuidCount === count ? $r('app.color.brand') : $r('app.color.text_secondary'))
            .onClick(() => { this.uuidCount = count; })
        }, (count: string) => count)
      }.width('100%')
    }.width('100%').padding(22).borderRadius(20).backgroundColor($r('app.color.surface'))
  }

  @Builder
  private diffResult() {
    Column({ space: 2 }) {
      ForEach(this.differences, (line: DiffLine) => {
        Row({ space: 8 }) {
          Text(line.oldLine > 0 ? line.oldLine.toString() : '').width(26).fontSize(11)
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.End)
          Text(line.newLine > 0 ? line.newLine.toString() : '').width(26).fontSize(11)
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.End)
          Text(line.kind === 'add' ? '+' : line.kind === 'remove' ? '−' : ' ').width(12).fontSize(13)
            .fontColor(line.kind === 'add' ? $r('app.color.success') : $r('app.color.error'))
          Text(line.text || ' ').fontSize(13).fontFamily('monospace').layoutWeight(1)
            .fontColor(line.kind === 'add' ? $r('app.color.success') :
              line.kind === 'remove' ? $r('app.color.error') : $r('app.color.text_primary'))
            .copyOption(CopyOptions.LocalDevice)
        }.width('100%').alignItems(VerticalAlign.Top).padding({ top: 6, bottom: 6, left: 6, right: 6 })
          .borderRadius(5).backgroundColor(line.kind === 'equal' ? Color.Transparent : $r('app.color.soft_surface'))
      }, (line: DiffLine) => line.kind + ':' + line.oldLine + ':' + line.newLine)
    }.width('100%')
  }

  @Builder
  private resultPanel() {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Text(this.activeToolId === 'diff' ? '对比结果 · − 删除 / + 新增' : '处理结果').fontSize(14)
          .fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button('复制', { type: ButtonType.Normal }).fontSize(13).fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_soft')).borderRadius(9).height(32)
          .padding({ left: 14, right: 14 }).onClick(() => { this.copy(); })
      }.width('100%')
      if (this.colorPreview) {
        Row() {
          Column().width(64).height(64).backgroundColor(this.colorPreview).borderRadius(14)
          Text(this.colorPreview).fontSize(23).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            .margin({ left: 18 })
        }.width('100%').padding({ top: 4, bottom: 8 })
      }
      if (this.activeToolId === 'diff') {
        this.diffResult()
      } else {
        if (this.output.length > 50000) {
          Text('预览前 50,000 个字符；复制可获取完整结果。').fontSize(11)
            .fontColor($r('app.color.text_secondary')).width('100%')
        }
        Text(this.output.substring(0, 50000)).fontSize(14).fontFamily('monospace').fontColor($r('app.color.text_primary'))
          .lineHeight(23).width('100%').copyOption(CopyOptions.LocalDevice)
          .padding(14).borderRadius(12).backgroundColor($r('app.color.soft_surface'))
      }
    }.width('100%').padding(18).backgroundColor($r('app.color.surface')).borderRadius(20)
  }

  @Builder
  private markdownBlock(block: MarkdownBlock) {
    if (block.kind === 'rule') {
      Divider().color($r('app.color.divider')).margin({ top: 8, bottom: 8 })
    } else if (block.kind === 'code') {
      Text(block.text).fontSize(13).fontFamily('monospace').fontColor($r('app.color.text_primary'))
        .lineHeight(22).copyOption(CopyOptions.LocalDevice).padding(14).width('100%')
        .backgroundColor($r('app.color.soft_surface')).borderRadius(10)
    } else {
      Text() {
        ForEach(block.inlines, (inline: MarkdownInline) => {
          Span(inline.text)
            .fontWeight(inline.kind === 'bold' || block.kind.startsWith('h') ? FontWeight.Bold : FontWeight.Regular)
            .fontStyle(inline.kind === 'italic' ? FontStyle.Italic : FontStyle.Normal)
            .fontFamily(inline.kind === 'code' ? 'monospace' : 'sans-serif')
            .fontColor(inline.kind === 'link' || inline.kind === 'code' ? $r('app.color.brand') :
              block.kind === 'quote' ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
        }, (inline: MarkdownInline, index: number) => index + ':' + inline.kind)
      }
      .fontSize(block.kind === 'h1' ? 26 : block.kind === 'h2' ? 22 : block.kind.startsWith('h') ? 18 : 15)
      .lineHeight(block.kind.startsWith('h') ? 34 : 26).width('100%')
      .copyOption(CopyOptions.LocalDevice)
      .padding(block.kind === 'quote' ? 12 : 0)
      .backgroundColor(block.kind === 'quote' ? $r('app.color.brand_soft') : Color.Transparent)
      .borderRadius(8)
    }
  }

  @Builder
  private markdownPreview() {
    Column({ space: 14 }) {
      Text('实时预览').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary')).width('100%')
      if (this.markdown.length === 0) {
        Text('文字将从这里慢慢亮起。').fontSize(14).fontColor($r('app.color.text_secondary'))
          .padding({ top: 22, bottom: 22 })
      } else {
        ForEach(this.markdown, (block: MarkdownBlock) => {
          this.markdownBlock(block)
        }, (block: MarkdownBlock, index: number) => index + ':' + block.kind + ':' + block.text)
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding(20).backgroundColor($r('app.color.surface')).borderRadius(20)
  }

  @Builder
  private pageTitleBar() {
    LumiBackHeader({
      title: findTool(this.activeToolId).title,
      showTutorial: true,
      tutorialEnabled: !this.isBusy,
      onTutorial: () => { LumiHelpNavigation.open(this.pathStack, this.activeToolId); },
      onBack: () => { this.pathStack.pop(); }
    })
  }

  build() {
    NavDestination() {
      Scroll(this.pageScroller) {
        Column({ space: 18 }) {
          Column({ space: 8 }) {
            Text('DEVELOPER TOOLS').fontSize(10).fontWeight(FontWeight.Bold).letterSpacing(2)
              .fontColor($r('app.color.brand')).width('100%')
            Text(findTool(this.activeToolId).description).fontSize(15).lineHeight(24)
              .fontColor($r('app.color.text_secondary')).width('100%')
          }.width('100%').padding({ top: 4, bottom: 4 })
          if (this.modes().length > 0) {
            this.modeSelector()
          }
          if (this.activeToolId === 'regex') {
            this.regexOptions()
          }
          if (this.activeToolId === 'uuid') {
            this.uuidOptions()
          } else {
            this.inputPanel(this.activeToolId === 'diff' ? '原始文本' : this.activeToolId === 'regex' ? '测试文本' : '输入内容')
          }
          if (this.activeToolId === 'diff') {
            this.inputPanel('修改后文本', true)
          }
          if (this.suggestion) {
            Row({ space: 8 }) {
              Text('识别到可能是' + findTool(this.suggestion).title + '内容').fontSize(12)
                .fontColor($r('app.color.brand')).layoutWeight(1)
              Button('前往工具', { type: ButtonType.Normal }).fontSize(12).height(32)
                .fontColor($r('app.color.brand')).backgroundColor(Color.Transparent)
                .onClick(() => this.selectTool(this.suggestion, true))
            }.padding(12).width('100%').backgroundColor($r('app.color.brand_soft')).borderRadius(12)
          }
          Text(this.note()).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%')
            .padding({ left: 4, right: 4 })
          if (this.activeToolId !== 'markdown') {
            Button(this.isBusy ? '处理中…' : this.actionTitle(), { type: ButtonType.Normal }).id('dev-execute')
              .height(52).width('100%').borderRadius(16).fontSize(16).fontWeight(FontWeight.Medium)
              .backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.isBusy)
              .onClick(() => { this.execute(); })
          }
          if (this.error) {
            Text(this.error).fontSize(13).lineHeight(21).fontColor($r('app.color.error')).width('100%')
              .padding(14).borderRadius(12).backgroundColor($r('app.color.surface')).accessibilityLevel('yes')
          } else if (this.status) {
            Text(this.status).fontSize(12).fontColor($r('app.color.success')).width('100%').padding({ left: 4, right: 4 })
          }
          if (this.activeToolId === 'markdown') {
            this.markdownPreview()
          } else if (this.output.length > 0) {
            this.resultPanel()
          }
          Row({ space: 12 }) {
            Text('保存本地草稿（关闭会清除全部开发者草稿）').fontSize(12).fontColor($r('app.color.text_secondary')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.draftEnabled }).id('dev-draft-toggle').onChange((enabled: boolean) => { this.setDraftEnabled(enabled); })
          }.width('100%')
          if (this.draftEnabled) { Button('清空本工具草稿').id('dev-draft-clear').onClick(() => this.clearDraft()) }
          if (this.activeToolId !== 'markdown') {
            Row({ space: 12 }) {
              Column({ space: 5 }) {
                Text('仅记录工具使用').fontSize(13).fontColor($r('app.color.text_primary')).width('100%')
                Text('默认关闭，开启后也不保存输入与结果正文').fontSize(11).lineHeight(17)
                  .fontColor($r('app.color.text_secondary')).width('100%')
              }.layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.recordUsage }).selectedColor($r('app.color.brand'))
                .onChange((enabled: boolean) => { this.recordUsage = enabled; })
                .accessibilityText('仅记录工具使用，不保存正文')
            }.width('100%').padding({ left: 4, right: 4, top: 6, bottom: 10 })
          }
        }.width('100%').padding({ left: 24, right: 24, top: 12, bottom: 40 + this.bottomInset })
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
      const param = context.pathInfo.param as DeveloperRouteParam;
      if (param) {
        this.toolId = param.toolId;
        this.selectTool(param.toolId);
      }
    })
    .backgroundColor($r('app.color.background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
