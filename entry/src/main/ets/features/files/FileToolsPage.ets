import { WorkbenchStore } from '../workbench/WorkbenchStore';
import { LumiFileSession, LumiCollection, LumiSavedPage } from '../workbench/WorkbenchModels';
import { LumiResultCard } from '../workbench/ResultCard';
import { camera, cameraPicker } from '@kit.CameraKit';
import { TextAreaPageScroll } from '../../core/TextAreaPageScroll';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { LumiHelpNavigation } from '../help/HelpNavigation';
import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { StorageService } from '../../core/StorageService';
import { TaskManager } from '../../core/TaskManager';
import { DataEngine } from './DataEngine';
import { processFiles, ProcessingOptions } from './FileProcessor';
import { AnalyticsRouteParam } from '../analytics/AnalyticsPage';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { preparePdfPages, LumiPdfPageEdit } from './PdfEnhancements';
import { LumiFilePreset, validFilePreset } from './FilePresets';
import { OcrService } from '../ocr/OcrService';
import { FilePreview } from './FilePreview';
import { EcosystemBridge } from '../../core/EcosystemBridge';
import { BatchFileService, LumiBatchOutcome, batchOutcomeLabel } from '../../core/BatchFileService';
import { WorkspaceSearch } from '../../core/WorkspaceSearch';

class FilePreviewRequest {
  id: number = 0;
  path: string = '';
  password: string = '';
}

export class FileToolRouteParam {
  toolId: string = 'file-workspace';
  filePath: string = '';
  filePaths: string[] = [];
  resume: boolean = false;
  capture: boolean = false;
}

@Builder
export function fileToolBuilder() {
  FileToolsPage()
}

@Component
export struct FileToolsPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State @Watch('scheduleSession') pdfPages: LumiPdfPageEdit[] = [];
  @State @Watch('scheduleSession') targetMB: string = '';
  @State presets: LumiFilePreset[] = [];
  @State presetName: string = '';
  @State selectedPresetId: string = '';
  @State workspaceQuery: string = '';
  @State workspaceCollection: string = '';
  @State showTrash: boolean = false;
  @State workspaceRole: string = '';
  @State workspaceSelecting: boolean = false;
  @State workspaceSelection: string[] = [];
  @State batchTags: string = '';
  @State batchCollectionId: string = '';
  @State libraryLimit: number = 20;
  @State collections: LumiCollection[] = [];
  @State sessionNotice: string = '';
  private sessionReady: boolean = false;
  private sessionCompleted: boolean = false;
  private sessionTimer: number = -1;
  private savedEdits: LumiSavedPage[] = [];
  private thumbnailPrefix: string = '';
  private draggedPage: number = -1;
  @State toolId: string = 'file-workspace';
  @State @Watch('scheduleSession') selected: WorkspaceFile[] = [];
  @State library: WorkspaceFile[] = [];
  @State outputs: WorkspaceFile[] = [];
  @State input: string = '';
  @State output: string = '';
  @State @Watch('scheduleSession') pages: string = '';
  @State password: string = '';
  @State @Watch('scheduleSession') format: number = 0;
  @State @Watch('scheduleSession') quality: number = 90;
  @State @Watch('scheduleSession') targetWidth: string = '';
  @State @Watch('scheduleSession') name: string = '';
  @State busy: boolean = false;
  @State canCancel: boolean = false;
  @State progress: number = 0;
  @State message: string = '';
  @State isError: boolean = false;
  @State previewRequests: FilePreviewRequest[] = [];
  @State showLibrary: boolean = false;
  private previewSequence: number = 0;
  private previewNeedsScroll: boolean = false;
  private currentTask: taskpool.Task | undefined = undefined;
  private cancelRequested: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private readonly pageScroller: Scroller = new Scroller();
  private readonly inputScroll: TextAreaPageScroll = new TextAreaPageScroll();

  private blockBackWhileBusy(): boolean {
    if (this.busy) {
      this.getUIContext().getPromptAction().showToast({ message: '任务处理中，请先完成或取消任务' });
      return true;
    }
    if (this.toolId === 'file-workspace' && this.workspaceSelecting) {
      this.workspaceSelecting = false; this.clearWorkspaceSelection(); return true;
    }
    return false;
  }
  private leavePage(): void {
    if (!this.blockBackWhileBusy()) { this.pathStack.pop(); }
  }
  aboutToAppear(): void { this.refresh(); this.loadPresets(); }
  aboutToDisappear(): void { if (this.sessionTimer >= 0) { clearTimeout(this.sessionTimer); } this.persistSession().catch(() => {}); this.sessionReady = false; this.cleanThumbnails(); }
  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async refresh(): Promise<void> {
    try {
      this.library = await FileService.list(this.ctx(), this.toolId === 'file-workspace');
      this.collections = await WorkbenchStore.collections();
      const outputPaths = this.outputs.map((file: WorkspaceFile) => file.path);
      this.outputs = this.library.filter((file: WorkspaceFile) => outputPaths.includes(file.path) && !file.trashedAt);
      this.workspaceSelection = this.workspaceSelection.filter((path: string): boolean => this.library.some((file: WorkspaceFile): boolean => file.path === path && !!file.trashedAt === this.showTrash));
    } catch (error) { this.fail(error as Error); }
  }
  private collectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '全部集合' }];
    return options.concat(this.collections.map((entry: LumiCollection): SelectOption => ({ value: entry.name })));
  }
  private batchCollectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '未归组' }];
    return options.concat(this.collections.map((group: LumiCollection): SelectOption => ({ value: group.name })));
  }
  private visibleLibrary(): WorkspaceFile[] {
    return this.library.filter((file: WorkspaceFile) => !!file.trashedAt === this.showTrash &&
      (!this.workspaceCollection || file.collectionId === this.workspaceCollection || this.library.some((related: WorkspaceFile) => related.collectionId === this.workspaceCollection && (related.sourcePaths || []).includes(file.path))) &&
      (!this.workspaceRole || (file.role || 'source') === this.workspaceRole) &&
      WorkspaceSearch.matches(file, this.workspaceQuery, this.collections));
  }
  private clearWorkspaceSelection(): void { this.workspaceSelection = []; }
  private selectWorkspaceFile(file: WorkspaceFile): void {
    if (this.busy) { return; }
    this.workspaceSelecting = true;
    if (this.workspaceSelection.includes(file.path)) { this.workspaceSelection = this.workspaceSelection.filter((path: string): boolean => path !== file.path); }
    else if (this.workspaceSelection.length >= BatchFileService.MAX_FILES) { this.message = '一次最多选择 100 个文件，请分批操作'; this.isError = true; }
    else { this.workspaceSelection = this.workspaceSelection.concat([file.path]); }
  }
  private selectVisibleWorkspace(): void {
    const visible = this.visibleLibrary();
    if (visible.length > BatchFileService.MAX_FILES) { this.message = '当前筛选超过 100 个文件，请缩小筛选范围或分批选择'; this.isError = true; return; }
    this.workspaceSelection = visible.map((file: WorkspaceFile): string => file.path);
  }
  private workspaceSelectedFiles(): WorkspaceFile[] {
    return this.library.filter((file: WorkspaceFile): boolean => this.workspaceSelection.includes(file.path));
  }
  private async runWorkspaceBatch(kind: string): Promise<void> {
    if (this.busy) { return; }
    const files = this.workspaceSelectedFiles();
    if (!files.length) { this.fail(new Error('请先选择文件')); return; }
    if (kind === 'tags' && !this.batchTags.split(/[,，]/).some((tag: string): boolean => !!tag.trim())) { this.fail(new Error('请填写要追加的标签，以逗号分隔')); return; }
    if (kind === 'trash') {
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '将所选文件移入回收站？', message: '将处理 ' + files.length.toString() + ' 个文件。关联物品、表单、材料包或未完成任务的文件会保留并说明原因。', buttons: [{ text: '取消', color: '#64748B' }, { text: '移入回收站', color: '#C44D62' }] });
      if (choice.index !== 1) { return; }
    }
    this.busy = true; this.message = '正在处理所选文件…'; this.isError = false;
    try {
      if (kind === 'share') { await BatchFileService.share(this.ctx(), files); this.message = '已打开所选文件的系统分享面板'; }
      else if (kind === 'export') { await BatchFileService.exportFiles(this.ctx(), files); this.message = '已导出 ' + files.length.toString() + ' 个文件'; }
      else if (kind === 'archive') {
        const archive = await BatchFileService.archive(this.ctx(), files, '文件合集');
        this.message = '已生成 ' + archive.name + '，可在工作区导出或分享';
      } else {
        const outcome: LumiBatchOutcome = await BatchFileService.organize(this.ctx(), files, kind, this.batchTags.split(/[,，]/), this.batchCollectionId);
        this.workspaceSelection = this.workspaceSelection.filter((path: string): boolean => !outcome.succeeded.includes(path));
        this.message = batchOutcomeLabel(outcome); this.isError = outcome.failed.length > 0;
      }
      await this.refresh();
    } catch (error) { this.fail(error as Error); }
    finally { this.busy = false; }
  }
  private scheduleSession(): void {
    if (!this.sessionReady || this.isText() || this.toolId === 'file-workspace') { return; }
    this.sessionCompleted = false;
    this.sessionNotice = '正在保存选择与设置…';
    if (this.sessionTimer >= 0) { clearTimeout(this.sessionTimer); }
    this.sessionTimer = setTimeout(() => { this.sessionTimer = -1; this.persistSession().catch((error: Error) => { this.sessionNotice = error.message; }); }, 250);
  }
  private async persistSession(): Promise<void> {
    if (!this.sessionReady || this.isText() || this.toolId === 'file-workspace' || this.sessionCompleted) { return; }
    const draft = new LumiFileSession(); draft.toolId = this.toolId; draft.paths = this.selected.map((file: WorkspaceFile) => file.path);
    draft.name = this.name; draft.pages = this.pages; draft.format = this.format; draft.quality = Math.round(this.quality);
    draft.targetWidth = this.targetWidth; draft.targetMB = this.targetMB; draft.updatedAt = Date.now();
    draft.edits = this.pdfPages.length ? this.pdfPages.map((page: LumiPdfPageEdit): LumiSavedPage => ({ original: page.original, rotation: page.rotation })) : this.savedEdits.slice();
    await WorkbenchStore.putFileSession(draft);
    if (this.sessionReady) { this.sessionNotice = draft.paths.length ? '选择与设置已自动保存，可从首页继续。' : ''; }
  }
  private async clearSession(): Promise<void> {
    if (this.sessionTimer >= 0) { clearTimeout(this.sessionTimer); this.sessionTimer = -1; }
    this.sessionCompleted = true;
    const draft = new LumiFileSession(); draft.toolId = this.toolId; await WorkbenchStore.putFileSession(draft);
    this.sessionNotice = '';
  }
  private async initializeRoute(param: FileToolRouteParam): Promise<void> {
    this.toolId = param.toolId; if (this.toolId === 'image-compress') { this.format = 1; this.quality = 80; } await this.refresh();
    try {
      const paths = param.filePaths?.length ? param.filePaths : param.filePath ? [param.filePath] : [];
      if (!paths.length && !this.isText() && this.toolId !== 'file-workspace') {
        const draft = (await WorkbenchStore.fileSessions()).find((entry: LumiFileSession) => entry.toolId === this.toolId);
        if (draft) {
          const restored: WorkspaceFile[] = [];
          for (const path of draft.paths) { const file = this.library.find((entry: WorkspaceFile) => entry.path === path); if (file) { restored.push(file); } }
          this.selected = restored;
          this.name = draft.name; this.pages = draft.pages; this.format = draft.format; this.quality = draft.quality;
          this.targetWidth = draft.targetWidth; this.targetMB = draft.targetMB; this.savedEdits = draft.edits;
          this.sessionNotice = this.selected.length === draft.paths.length ? '已恢复上次选择与设置；密码需重新输入。' : '已恢复可用文件；部分文件已移除，请检查后继续。';
          if (this.toolId === 'pdf-edit' && this.selected.length) { await this.loadPdfPages(); }
        }
      } else { for (const path of paths) { await this.resolveInitialFile(path); } }
      this.sessionReady = true;
      if (param.capture) { await this.captureImage(); }
    } catch (error) { this.fail(error as Error); this.sessionReady = true; }
  }
  private async captureImage(): Promise<void> {
    try {
      const result = await cameraPicker.pick(this.ctx(), [cameraPicker.PickerMediaType.PHOTO], { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK });
      if (result.resultUri) { const files = await FileService.importUris(this.ctx(), [result.resultUri]); this.selected = files; await this.refresh(); }
    } catch (error) { this.fail(error as Error); }
  }
  private async resolveInitialFile(filePath: string): Promise<void> {
    if (!filePath) { return; }
    try {
      const library = await FileService.list(this.ctx());
      const file = library.find((entry: WorkspaceFile) => entry.path === filePath);
      if (file) { this.addFromLibrary(file); }
    } catch (_) { /* 文件不可用时保持初始状态 */ }
  }
  private continueTo(toolId: string, file: WorkspaceFile): void {
    if (toolId === 'analytics') {
      const param = new AnalyticsRouteParam();
      param.filePath = file.path;
      this.pathStack.pushPathByName('analytics', param);
      return;
    }
    const param = new FileToolRouteParam();
    param.toolId = toolId;
    param.filePath = file.path;
    this.pathStack.pushPathByName('fileTool', param);
  }
  private title(): string {
    switch (this.toolId) {
      case 'image-compress': return '图片压缩'; case 'pdf-edit': return 'PDF 页面整理'; case 'pdf-compress': return 'PDF 压缩'; case 'image-ocr': return '图片文字识别';
      case 'pdf-merge': return '合并 PDF'; case 'pdf-split': return '拆分 PDF'; case 'pdf-extract': return '提取 PDF 页面';
      case 'pdf-images': return 'PDF 转图片'; case 'images-pdf': return '图片转 PDF'; case 'image-convert': return '图片格式转换';
      case 'csv-json': return 'CSV 转 JSON'; case 'json-csv': return 'JSON 转 CSV'; case 'text-convert': return '文本格式转换';
      default: return '文件工作区';
    }
  }
  private isText(): boolean { return ['csv-json', 'json-csv', 'text-convert'].includes(this.toolId); }
  private needsImage(): boolean { return ['image-convert', 'image-compress', 'images-pdf', 'image-ocr'].includes(this.toolId); }
  private usesOutputPrefix(): boolean { return ['image-convert', 'image-compress', 'pdf-split', 'pdf-images'].includes(this.toolId); }
  private defaultOutputName(): string {
    if (this.selected.length > 0) {
      const sourceName = this.selected[0].name.replace(/\.[^.]+$/, '').trim();
      if (sourceName) { return sourceName; }
    }
    switch (this.toolId) {
      case 'pdf-merge': return '合并文档';
      case 'pdf-split': return '拆分页面';
      case 'pdf-extract': return '提取页面';
      case 'pdf-images': return 'PDF页面';
      case 'images-pdf': return '图片合集';
      case 'image-convert': return '转换图片';
      case 'csv-json': case 'json-csv': return '转换数据';
      default: return '转换文本';
    }
  }
  private outputBaseName(): string {
    const enteredName = this.name.trim().replace(/\.(pdf|png|jpe?g|webp|csv|json|txt|md)$/i, '').trim();
    const baseName = enteredName && !/^\.+$/.test(enteredName) ? enteredName : this.defaultOutputName();
    return FileService.cleanName(baseName).slice(0, 96);
  }
  private outputNameHint(): string {
    const baseName = this.outputBaseName();
    if (this.toolId === 'pdf-split' || this.toolId === 'pdf-images') {
      return '无需填写扩展名；按原页码自动编号，如“' + baseName + '_page_1.' + (this.toolId === 'pdf-split' ? 'pdf' : 'png') + '”。';
    }
    if (['image-convert', 'image-compress'].includes(this.toolId)) {
      const extension = this.format === 1 ? 'jpg' : this.format === 2 ? 'webp' : 'png';
      return '无需填写扩展名；按上方文件顺序自动编号，如“' + baseName + '_1.' + extension + '”。';
    }
    const extension = this.toolId === 'image-ocr' ? 'txt' : this.toolId === 'csv-json' ? 'json' : this.toolId === 'json-csv' ? 'csv' : this.toolId === 'text-convert' ? (this.format === 0 ? 'md' : 'txt') : 'pdf';
    return '无需填写扩展名，将自动保存为“' + baseName + '.' + extension + '”。';
  }
  private fail(error: Error): void { this.message = error.message || '处理失败，请检查文件后重试'; this.isError = true; }
  private updateTextInput(value: string): void {
    this.input = value;
    this.output = '';
    this.outputs = [];
    this.message = '';
    this.isError = false;
  }
  private async pick(): Promise<void> {
    try {
      this.message = '';
      if (this.isText()) {
        const file = await FileService.pickText(this.ctx()); this.updateTextInput(file.content); this.name = file.name.replace(/\.[^.]+$/, '');
      } else {
        const filters = this.toolId === 'file-workspace' ? [] : this.needsImage() ? ['图片|.png,.jpg,.jpeg,.webp,.heic'] : ['PDF|.pdf'];
        const max = ['pdf-merge', 'images-pdf', 'image-convert', 'image-compress', 'file-workspace'].includes(this.toolId) ? 20 : 1;
        const picked = await FileService.pickFiles(this.ctx(), filters, max);
        if (picked.length > 0) { this.savedEdits = []; this.cleanThumbnails(); this.selected = max === 1 ? picked.slice(0, 1) : this.selected.concat(picked).slice(0, max); }
      }
      await this.refresh();
    } catch (error) { this.fail(error as Error); }
  }
  private async addFromLibrary(file: WorkspaceFile): Promise<void> {
    if (this.isText()) {
      if (file.size > FileService.MAX_TEXT_BYTES) { this.fail(new Error('文本上限 4 MB')); return; }
      try { this.updateTextInput(await FileService.readText(this.ctx(), file.path)); this.name = file.name.replace(/\.[^.]+$/, ''); } catch (error) { this.fail(error as Error); }
    } else if (this.toolId === 'file-workspace') {
      if (file.mime === 'application/pdf' || file.mime.startsWith('image/')) { this.preview(file); }
    } else if (this.needsImage() ? file.mime.startsWith('image/') : file.mime === 'application/pdf') {
      if (!this.selected.some((entry: WorkspaceFile) => entry.id === file.id)) {
        this.savedEdits = []; this.cleanThumbnails();
        this.selected = ['pdf-merge', 'images-pdf', 'image-convert', 'image-compress'].includes(this.toolId) ? this.selected.concat([file]).slice(0, 20) : [file];
      }
    } else { this.fail(new Error(this.needsImage() ? '此工具需要图片文件' : '此工具需要 PDF 文件')); }
    this.showLibrary = false;
  }
  private nextActions(file: WorkspaceFile): MenuElement[] {
    if (file.mime === 'application/pdf') {
      return [{ value: '压缩 PDF', action: () => this.continueTo('pdf-compress', file) },
        { value: '整理页面', action: () => this.continueTo('pdf-edit', file) }, { value: '合并 PDF', action: () => this.continueTo('pdf-merge', file) },
        { value: '拆分 PDF', action: () => this.continueTo('pdf-split', file) },
        { value: '提取页面', action: () => this.continueTo('pdf-extract', file) },
        { value: 'PDF 转图片', action: () => this.continueTo('pdf-images', file) }];
    }
    if (file.mime.startsWith('image/')) {
      return [{ value: '压缩图片', action: () => this.continueTo('image-compress', file) }, { value: '识别文字', action: () => this.continueTo('image-ocr', file) }, { value: '转换图片格式', action: () => this.continueTo('image-convert', file) },
        { value: '生成 PDF', action: () => this.continueTo('images-pdf', file) }];
    }
    if (file.name.toLowerCase().endsWith('.xlsx')) { return [{ value: '表格数据分析', action: () => this.continueTo('analytics', file) }]; }
    if (file.mime === 'text/csv') {
      return [{ value: 'CSV 转 JSON', action: () => this.continueTo('csv-json', file) },
        { value: '本地数据分析', action: () => this.continueTo('analytics', file) }];
    }
    return [{ value: file.mime === 'application/json' ? 'JSON 转 CSV' : '文本格式转换',
      action: () => this.continueTo(file.mime === 'application/json' ? 'json-csv' : 'text-convert', file) }];
  }
  private async preview(file: WorkspaceFile): Promise<void> {
    try { FileService.assertOwned(this.ctx(), file.path); } catch (error) { this.fail(error as Error); return; }
    if(file.mime === 'application/pdf' && !canIUse('SystemCapability.OfficeService.PDFService.Core')) { this.fail(new Error('当前设备不支持 PDF 服务，请使用支持 PDF Kit 的设备')); return; }
    const request = new FilePreviewRequest();
    request.id = ++this.previewSequence;
    request.path = file.path;
    request.password = this.password;
    this.previewNeedsScroll = true;
    this.previewRequests = [request];
  }
  private reorder(index: number, delta: number): void {
    const files = this.selected.slice(); const other = index + delta;
    if (other < 0 || other >= files.length) { return; }
    const entry = files[index]; files[index] = files[other]; files[other] = entry; this.selected = files;
  }
  private async convertText(): Promise<boolean> {
    this.output = '';
    this.outputs = [];
    try {
      if (!this.input.trim()) { throw new Error('请导入或输入内容'); }
      if (this.input.length > FileService.MAX_TEXT_BYTES) { throw new Error('文本上限为 4 MB'); }
      if (this.toolId === 'csv-json') { this.output = DataEngine.json(DataEngine.parseCSV(this.input)); }
      else if (this.toolId === 'json-csv') { this.output = DataEngine.csv(DataEngine.fromJSON(this.input)); }
      else { this.output = this.input.replace(/\r\n/g, '\n'); }
      this.message = '转换完成，可预览或保存结果'; this.isError = false; return true;
    } catch (error) { this.fail(error as Error); return false; }
  }
  private async run(): Promise<void> {
    if (this.busy) { return; }
    if (this.toolId === 'image-ocr') { await this.recognizeImage(); return; }
    if (this.isText()) {
      let recordId = '';
      this.busy = true;
      try {
        recordId = await TaskManager.begin(this.toolId, this.title(), []);
        await TaskManager.running(recordId);
        if (await this.convertText()) { await TaskManager.complete(recordId, []); }
        else { await TaskManager.fail(recordId, '文本转换失败，请检查输入内容后重试。'); }
      } catch (error) {
        this.fail(error as Error);
        if (recordId) { try { await TaskManager.fail(recordId, '文本转换未完成，请重新输入后重试。'); } catch (_) { this.message += '；任务状态未能保存'; } }
      } finally { this.busy = false; }
      return;
    }
    if (this.selected.length === 0) { this.fail(new Error('请先添加文件')); return; }
    if (this.toolId === 'pdf-merge' && this.selected.length < 2) { this.fail(new Error('合并需要至少两个 PDF')); return; }
    if (this.toolId === 'pdf-edit' && !this.pdfPages.length) { this.fail(new Error('请先载入页面缩略图')); return; }
    if (['pdf-compress', 'image-compress'].includes(this.toolId) && this.targetMB && (!Number.isFinite(Number(this.targetMB)) || Number(this.targetMB) <= 0 || Number(this.targetMB) > 100)) { this.fail(new Error('目标大小请输入 0 至 100 MB 之间的数值')); return; }
    const width = this.targetWidth.trim() ? Number(this.targetWidth) : 0;
    if (!Number.isInteger(width) || width < 0 || width > 8192 || (this.targetWidth.trim() !== '' && width === 0)) { this.fail(new Error('最长宽度请输入 1 至 8192 的整数，留空保持原尺寸')); return; }
    if(!['image-convert', 'image-compress'].includes(this.toolId) && !canIUse('SystemCapability.OfficeService.PDFService.Core')) { this.fail(new Error('当前设备不支持 PDF 服务，请使用支持 PDF Kit 的设备')); return; }
    try { this.selected.forEach((file:WorkspaceFile) => FileService.assertOwned(this.ctx(),file.path)); } catch(error) { this.fail(error as Error); return; }
    this.busy = true; this.progress = 0; this.cancelRequested = false; this.message = '正在本地处理，请稍候…'; this.isError = false; this.outputs = [];
    let recordId = '';
    try {
      recordId = await TaskManager.begin(this.toolId, this.title(), this.selected.map((file: WorkspaceFile) => file.path));
      await TaskManager.running(recordId);
    const extension = this.format === 1 ? 'jpg' : this.format === 2 ? 'webp' : 'png';
    const baseName = this.outputBaseName();
    const names: string[] = ['image-convert', 'image-compress'].includes(this.toolId) ? this.selected.map((_file: WorkspaceFile, index: number) => baseName + '_' + (index + 1).toString() + '.' + extension) : [baseName + (['pdf-split','pdf-images'].includes(this.toolId) ? '' : '.pdf')];
    const paths = names.map((name: string) => FileService.outputPath(this.ctx(), name));
    const options: ProcessingOptions = { tool: this.toolId, inputs: this.selected.map((file: WorkspaceFile) => file.path), outputs: paths,
      pages: this.pages, quality: Math.round(this.quality), width: width, format: 'image/' + (extension === 'jpg' ? 'jpeg' : extension), password: this.password, targetBytes: Number(this.targetMB) * 1024 * 1024,
      // TaskPool cannot serialize ArkUI state proxies, including an empty @State array.
      editPages: this.pdfPages.map((page: LumiPdfPageEdit): LumiPdfPageEdit => ({
        original: page.original, rotation: page.rotation, thumbnail: page.thumbnail
      })) };
      this.currentTask = new taskpool.Task(processFiles, options);
      this.canCancel = true;
      const currentRecordId = recordId;
      this.currentTask.onReceiveData((value: number) => {
        this.progress = value;
        TaskManager.progress(currentRecordId, value).catch(() => {});
      });
      const results = await taskpool.execute(this.currentTask) as string[];
      const files: WorkspaceFile[] = [];
      for (let index = 0; index < results.length; index++) {
        const path = results[index];
        const resultName = ['image-convert', 'image-compress'].includes(this.toolId) ? names[paths.indexOf(path)] : path.substring(path.lastIndexOf('/') + 1).replace(/^\d+_\d+_/, '');
        files.push(await FileService.register(this.ctx(), path, resultName));
      }
      for (const file of files) { file.sourcePaths = ['image-convert', 'image-compress'].includes(this.toolId) ? [this.selected[paths.indexOf(file.path)].path] : this.selected.map((source: WorkspaceFile) => source.path); file.role = 'final'; await FileService.updateDetails(this.ctx(), file); }
      await TaskManager.complete(recordId, results);
      await this.clearSession();
      this.outputs = files; this.message = '处理完成 · ' + files.length.toString() + ' 个结果已保存到工作区';
      if (this.toolId === 'image-compress' && files.length) {
        const before = files.reduce((sum: number, file: WorkspaceFile) => sum + this.selected[paths.indexOf(file.path)].size, 0);
        const after = files.reduce((sum: number, file: WorkspaceFile) => sum + file.size, 0);
        this.message = '已压缩 ' + files.length.toString() + ' 张：' + FileService.sizeLabel(before) + ' → ' + FileService.sizeLabel(after) + '，减少 ' + Math.round((1 - after / before) * 100).toString() + '%。原图已保留。';
        if (files.length < this.selected.length) { this.message += '跳过 ' + (this.selected.length - files.length).toString() + ' 张未能进一步缩小的图片。'; }
        const overTarget = files.filter((file: WorkspaceFile) => Number(this.targetMB) > 0 && file.size > Number(this.targetMB) * 1024 * 1024).length;
        if (overTarget) { this.message += overTarget.toString() + ' 张尚未达到目标大小，可调整设置后重试。'; }
      }
      if (this.toolId === 'pdf-compress' && files.length) {
        this.message = '压缩前 ' + FileService.sizeLabel(this.selected[0].size) + ' → 压缩后 ' + FileService.sizeLabel(files[0].size) + '，减少 ' + Math.round((1 - files[0].size / this.selected[0].size) * 100).toString() + '%。';
        if (Number(this.targetMB) > 0 && files[0].size > Number(this.targetMB) * 1024 * 1024) { this.message += '尚未达到目标大小，可调整质量后重试。'; }
      }
      await StorageService.addHistory(this.toolId, this.title(), this.selected.length.toString() + ' 个输入 · ' + files.length.toString() + ' 个输出', files[0]?.path || '');
      await this.refresh();
    } catch (error) {
      this.fail(error as Error);
      if (recordId) {
        try { await TaskManager.fail(recordId, this.cancelRequested ? '用户已取消任务，可调整参数后重试。' : this.message, this.cancelRequested); }
        catch (_) { this.message += '；任务状态未能保存'; }
      }
    }
    finally { this.busy = false; this.canCancel = false; this.currentTask = undefined; this.cancelRequested = false; }
  }
  private async saveText(): Promise<void> {
    try {
      const suffix = this.toolId === 'csv-json' ? '.json' : this.toolId === 'json-csv' ? '.csv' : this.toolId === 'image-ocr' ? '.txt' : this.format === 0 ? '.md' : '.txt';
      const outputName = this.outputBaseName() + suffix;
      const path = await FileService.writeText(this.ctx(), outputName, this.output);
      const file = await FileService.list(this.ctx()); this.outputs = file.filter((entry: WorkspaceFile) => entry.path === path);
      for (const result of this.outputs) { result.role = 'final'; result.sourcePaths = this.selected.map((source: WorkspaceFile) => source.path); await FileService.updateDetails(this.ctx(), result); }
      await this.clearSession();
      await FileService.exportFile(this.ctx(), path, outputName);
      await StorageService.addHistory(this.toolId, this.title(), '已导出 ' + outputName, path);
      this.message = '文件已导出'; this.isError = false;
    } catch (error) { this.fail(error as Error); }
  }
  private async exportResult(file: WorkspaceFile): Promise<void> {
    try { await FileService.exportFile(this.ctx(), file.path, file.name); this.message = '已导出 ' + file.name; this.isError = false; }
    catch (error) { this.fail(error as Error); }
  }
  private async shareResult(file: WorkspaceFile): Promise<void> { try { await FileService.share(this.ctx(), file.path, file.name); } catch (error) { this.fail(error as Error); } }
  private async remove(file: WorkspaceFile): Promise<void> {
    try { await FileService.remove(this.ctx(), file); await this.refresh(); this.message = '已移除工作区副本'; this.isError = false; } catch (error) { this.fail(error as Error); }
  }

  private async loadPresets(): Promise<void> {
    try { const saved = JSON.parse(await StorageService.getValue('file.presets', '[]')) as LumiFilePreset[]; this.presets = saved.filter(validFilePreset); }
    catch (_) { this.fail(new Error('预设无法读取，请稍后重试')); }
  }
  private applyPreset(preset: LumiFilePreset): void {
    this.format = preset.format; this.quality = preset.quality; this.targetWidth = preset.width; this.targetMB = preset.targetMB;
    this.selectedPresetId = preset.id; this.presetName = preset.name;
  }
  private async savePreset(): Promise<void> {
    const preset = new LumiFilePreset(); preset.id = this.selectedPresetId || Date.now().toString(); preset.name = this.presetName.trim();
    preset.tool = this.toolId; preset.format = this.format; preset.quality = this.quality; preset.width = this.targetWidth; preset.targetMB = this.targetMB;
    if (!validFilePreset(preset)) { this.fail(new Error('请填写 1–40 字的预设名，并检查宽度和目标大小')); return; }
    const next = [preset].concat(this.presets.filter((entry: LumiFilePreset) => entry.id !== preset.id));
    if (next.length > 30) { this.fail(new Error('最多保存 30 个预设，请先删除不再使用的预设')); return; }
    try { await StorageService.setValue('file.presets', JSON.stringify(next)); this.presets = next; this.selectedPresetId = preset.id; this.message = '处理预设已保存'; this.isError = false; }
    catch (error) { this.fail(error as Error); }
  }
  private async deletePreset(): Promise<void> {
    try { const next = this.presets.filter((entry: LumiFilePreset) => entry.id !== this.selectedPresetId); await StorageService.setValue('file.presets', JSON.stringify(next)); this.presets = next; this.selectedPresetId = ''; this.presetName = ''; }
    catch (error) { this.fail(error as Error); }
  }
  private cleanThumbnails(): void {
    this.pdfPages = [];
    if (!this.thumbnailPrefix) { return; }
    try { const folder = this.thumbnailPrefix.substring(0, this.thumbnailPrefix.lastIndexOf('/')); const prefix = this.thumbnailPrefix.substring(this.thumbnailPrefix.lastIndexOf('/') + 1);
      for (const name of fs.listFileSync(folder)) { if (name.startsWith(prefix + '_')) { fs.unlinkSync(folder + '/' + name); } }
    } catch (_) {} this.thumbnailPrefix = '';
  }
  private async loadPdfPages(): Promise<void> {
    if (this.busy || !this.selected.length) { return; }
    this.cleanThumbnails(); this.busy = true;
    try {
      this.thumbnailPrefix = this.ctx().cacheDir + '/pdfthumb_' + Date.now().toString();
      const loaded = await taskpool.execute(preparePdfPages, this.selected[0].path, this.password, this.thumbnailPrefix) as LumiPdfPageEdit[];
      this.pdfPages = this.savedEdits.length ? this.savedEdits.map((saved: LumiSavedPage): LumiPdfPageEdit => ({ original: saved.original, rotation: saved.rotation, thumbnail: loaded.find((page: LumiPdfPageEdit) => page.original === saved.original)?.thumbnail || '' })) : loaded;
      this.savedEdits = [];
      this.message = '长按缩略图拖动排序，也可使用上移按钮；原文件保留。'; this.isError = false;
    } catch (error) { this.cleanThumbnails(); this.fail(error as Error); }
    finally { this.busy = false; }
  }
  private movePdf(from: number, to: number): void {
    if (from < 0 || to < 0 || from >= this.pdfPages.length || to >= this.pdfPages.length) { return; }
    const pages = this.pdfPages.slice(); pages.splice(to, 0, pages.splice(from, 1)[0]); this.pdfPages = pages;
  }
  private rotatePdf(original: number): void {
    this.pdfPages = this.pdfPages.map((page: LumiPdfPageEdit) => {
      const result = new LumiPdfPageEdit(); result.original = page.original; result.thumbnail = page.thumbnail;
      result.rotation = page.original === original ? (page.rotation + 90) % 360 : page.rotation; return result;
    });
  }
  private async recognizeImage(): Promise<void> {
    if (!this.selected.length) { this.fail(new Error('请先选择图片')); return; }
    this.busy = true; this.output = ''; let recordId = '';
    try {
      FileService.assertOwned(this.ctx(), this.selected[0].path);
      recordId = await TaskManager.begin('image-ocr', '图片文字识别', [this.selected[0].path]); await TaskManager.running(recordId);
      this.output = await OcrService.recognize(this.selected[0].path);
      await TaskManager.complete(recordId, []); this.message = '识别完成，请对照原图核对，可编辑、复制或保存文字。'; this.isError = false;
    } catch (error) { this.fail(error as Error); if (recordId) { await TaskManager.fail(recordId, this.message); } }
    finally { this.busy = false; }
  }
  private async copyOcr(): Promise<void> {
    try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.output)); this.message = '识别文字已复制'; this.isError = false; }
    catch (error) { this.fail(error as Error); }
  }
  private async shareOcrToLexiNote(): Promise<void> {
    try {
      const baseTitle = this.outputBaseName();
      const md = EcosystemBridge.buildOcrNoteMarkdown(baseTitle, this.output, this.selected[0]?.name || '');
      await EcosystemBridge.shareMarkdownToLexiNote(this.ctx(), baseTitle, md, this.toolId, '沉淀识别文字到知萤笔记');
      await this.refresh();
      this.message = '已生成双链 Markdown 并保存在工作区，可在分享面板选择「知萤」';
      this.isError = false;
    } catch (error) {
      this.fail(error as Error);
    }
  }
  private async sendOcrToLexiGlow(asArticle: boolean): Promise<void> {
    try {
      await EcosystemBridge.openInLexiGlow(this.ctx(), this.outputBaseName(), this.output, asArticle);
      this.message = asArticle ? '已发送至词萤伴读' : '已发送至词萤提取生词';
      this.isError = false;
    } catch (error) {
      this.fail(error as Error);
    }
  }

  @Builder
  private pdfOrganizer() {
    Column({ space: 12 }) {
      Button('载入 / 重置页面缩略图').id('pdf-load-pages').width('100%').onClick(() => this.loadPdfPages()).enabled(!this.busy && this.selected.length > 0)
      ForEach(this.pdfPages, (page: LumiPdfPageEdit, index: number) => {
        Row({ space: 14 }) {
          Image(fileUri.getUriFromPath(page.thumbnail)).width(80).height(105).objectFit(ImageFit.Contain).rotate({ angle: page.rotation })
          Column({ space: 8 }) {
            Text('第 ' + (index + 1).toString() + ' 位 · 原第 ' + (page.original + 1).toString() + ' 页').fontSize(13).fontColor($r('app.color.text_primary'))
            Row({ space: 6 }) {
              Button('上移').fontSize(12).enabled(index > 0 && !this.busy).onClick(() => this.movePdf(index, index - 1))
              Button('旋转').fontSize(12).enabled(!this.busy).onClick(() => this.rotatePdf(page.original))
              Button('删除').fontSize(12).enabled(this.pdfPages.length > 1 && !this.busy).onClick(() => { this.pdfPages = this.pdfPages.filter((entry: LumiPdfPageEdit) => entry.original !== page.original); })
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.draggable(!this.busy).onDragStart(() => { this.draggedPage = page.original; }).onDrop(() => {
          this.movePdf(this.pdfPages.findIndex((entry: LumiPdfPageEdit) => entry.original === this.draggedPage), index);
        }).width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(16)
      }, (page: LumiPdfPageEdit, pageIndex: number) => page.original.toString() + '_' + page.rotation.toString() + '_' + pageIndex.toString())
    }.width('100%')
  }
  @Builder
  private sectionLabel(title: string, caption: string) {
    Column({ space: 5 }) { Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')); Text(caption).fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(19); }.alignItems(HorizontalAlign.Start).width('100%')
  }
  @Builder
  private resultRow(file: WorkspaceFile, workspace: boolean) {
    LumiResultCard({ file: file, onChanged: () => { this.refresh(); }, actions: this.nextActions(file),
      selectable: workspace, selecting: workspace && this.workspaceSelecting,
      selectionChecked: this.workspaceSelection.includes(file.path),
      onSelect: () => { this.selectWorkspaceFile(file); }, onLongSelect: () => { this.selectWorkspaceFile(file); } })
      .enabled(!this.busy)
  }

  @Builder
  private workspaceBatchBar() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text('已选择 ' + this.workspaceSelection.length.toString() + ' 个').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        Button('全选筛选结果').id('workspace-select-all').fontSize(12).onClick(() => { this.selectVisibleWorkspace(); })
        Button('清空').fontSize(12).onClick(() => { this.clearWorkspaceSelection(); })
      }.width('100%')
      if (!this.showTrash) {
        Row({ space: 8 }) {
          Button('导出所选').id('workspace-batch-export').layoutWeight(1).fontSize(13).onClick(() => { this.runWorkspaceBatch('export'); })
          Button('分享所选').id('workspace-batch-share').layoutWeight(1).fontSize(13).onClick(() => { this.runWorkspaceBatch('share'); })
          Button('ZIP 打包').id('workspace-batch-archive').layoutWeight(1).fontSize(13).onClick(() => { this.runWorkspaceBatch('archive'); })
        }.width('100%')
        Row({ space: 8 }) {
          TextInput({ text: this.batchTags, placeholder: '追加标签，以逗号分隔' }).id('workspace-batch-tags').maxLength(240).layoutWeight(1).onChange((text: string) => { this.batchTags = text; })
          Button('添加标签').fontSize(12).onClick(() => { this.runWorkspaceBatch('tags'); })
        }.width('100%')
        Row({ space: 8 }) {
          Select(this.batchCollectionOptions()).value(this.collections.find((group: LumiCollection): boolean => group.id === this.batchCollectionId)?.name || '未归组').onSelect((index: number) => { this.batchCollectionId = index > 0 ? this.collections[index - 1].id : ''; }).layoutWeight(1)
          Button('移入集合').fontSize(12).onClick(() => { this.runWorkspaceBatch('collection'); })
        }.width('100%')
        Button('移入回收站').id('workspace-batch-trash').fontColor($r('app.color.error')).width('100%').onClick(() => { this.runWorkspaceBatch('trash'); })
      } else {
        Button('恢复所选文件').id('workspace-batch-restore').width('100%').onClick(() => { this.runWorkspaceBatch('restore'); })
      }
      Text('每批最多 100 个文件；导出、分享与打包总大小不超过 500 MB。').fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
    }.padding(16).width('100%').backgroundColor($r('app.color.brand_soft')).borderRadius(20).enabled(!this.busy)
  }

  @Builder
  private pageTitleBar() {
    LumiBackHeader({
      title: this.title(),
      showTutorial: true,
      tutorialEnabled: !this.busy,
      onTutorial: () => { LumiHelpNavigation.open(this.pathStack, this.toolId); },
      onBack: () => { this.leavePage(); }
    })
  }

  build() {
    NavDestination() {
      Scroll(this.pageScroller) {
        Column({ space: 18 }) {
          if (this.toolId === 'file-workspace') {
            this.sectionLabel('你的文件，集中有序', '导入副本与处理结果都保存在这里，可继续导出、预览和分享。')
            Row({ space: 8 }) {
              Button('＋ 导入文件').layoutWeight(1).height(52).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(() => this.pick())
              Button(this.workspaceSelecting ? '退出多选' : '多选整理').id('workspace-select-mode').height(52).fontColor($r('app.color.brand')).onClick(() => { this.workspaceSelecting = !this.workspaceSelecting; this.clearWorkspaceSelection(); })
            }.width('100%').enabled(!this.busy)
            if (this.library.length === 0) { Text('工作区还是空的\n导入第一份文件，开始你的工作流。').fontSize(15).fontColor($r('app.color.text_secondary')).lineHeight(25).textAlign(TextAlign.Center).padding(40) }
            TextInput({ text: this.workspaceQuery, placeholder: '搜索文件名、标签或集合' }).id('workspace-search').enabled(!this.busy).onChange((text: string) => { this.workspaceQuery = text; this.libraryLimit = 20; this.clearWorkspaceSelection(); })
            Row({ space: 8 }) {
              Button(this.showTrash ? '查看工作区' : '回收站').id('workspace-trash').onClick(() => { this.showTrash = !this.showTrash; this.libraryLimit = 20; this.clearWorkspaceSelection(); })
              Select(this.collectionOptions()).value(this.collections.find((entry: LumiCollection) => entry.id === this.workspaceCollection)?.name || '全部集合').onSelect((index: number) => { this.workspaceCollection = index > 0 ? this.collections[index - 1].id : ''; this.libraryLimit = 20; this.clearWorkspaceSelection(); })
            }.width('100%').enabled(!this.busy)
            Select([{ value: '全部文件' }, { value: '原件' }, { value: '中间结果' }, { value: '最终成果' }]).value(this.workspaceRole === 'source' ? '原件' : this.workspaceRole === 'intermediate' ? '中间结果' : this.workspaceRole === 'final' ? '最终成果' : '全部文件').enabled(!this.busy).onSelect((index: number) => { this.workspaceRole = ['', 'source', 'intermediate', 'final'][index]; this.libraryLimit = 20; this.clearWorkspaceSelection(); })
            if (this.workspaceSelecting) { this.workspaceBatchBar() }
            if (this.showTrash) { Text('恢复后会保留原来的集合、标签和来源。').fontSize(12).fontColor($r('app.color.text_secondary')) }
            if (this.visibleLibrary().length === 0) { Text('没有符合条件的文件').fontColor($r('app.color.text_secondary')).padding(24) }
            ForEach(this.visibleLibrary().slice(0, this.libraryLimit), (file: WorkspaceFile) => { this.resultRow(file, true) }, (file: WorkspaceFile) => JSON.stringify(file))
            if (this.visibleLibrary().length > this.libraryLimit) { Button('显示更多').onClick(() => { this.libraryLimit += 20; }) }
          } else {
            if (this.sessionNotice) {
              Text(this.sessionNotice).fontSize(12).fontColor($r('app.color.brand')).width('100%')
              Button('清除本次草稿', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy).onClick(() => { this.selected = []; this.cleanThumbnails(); this.clearSession(); })
            }
            this.sectionLabel(this.isText() ? '从一份文本开始' : '从一份文件开始', this.isText() ? '导入 UTF-8 文本，或直接粘贴内容。' : '原文件保持只读，处理结果生成独立副本。每批最多 20 个文件。')
            Row({ space: 10 }) {
              Button('＋ ' + (this.isText() ? '导入文本' : '添加文件')).layoutWeight(1).height(50).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(() => this.pick()).enabled(!this.busy)
              Button('从工作区选择').layoutWeight(1).height(50).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => { this.showLibrary = !this.showLibrary; this.refresh(); }).enabled(!this.busy)
            }.width('100%')
            if (this.showLibrary) {
              Column({ space: 8 }) {
                if (this.library.length === 0) { Text('还没有工作区文件').fontColor($r('app.color.text_secondary')).padding(16) }
                ForEach(this.library.slice(0, 30), (file: WorkspaceFile) => { Text(file.name).fontSize(14).fontColor($r('app.color.text_primary')).padding(14).width('100%').backgroundColor($r('app.color.surface')).borderRadius(12).onClick(() => this.addFromLibrary(file)) }, (file: WorkspaceFile) => file.id)
              }.width('100%')
            }
            if (this.isText()) {
              TextArea({ text: this.input, placeholder: this.toolId === 'json-csv' ? '[{"姓名":"小林","城市":"杭州"}]' : this.toolId === 'csv-json' ? '姓名,城市\n小林,杭州' : '输入或粘贴 TXT / Markdown 文本' }).id('file-text-input').attributeModifier(this.inputScroll).height(210).fontSize(14).fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.surface')).borderRadius(18).onChange((value: string) => { this.updateTextInput(value); })
              Text(this.toolId === 'text-convert' ? 'TXT 与 Markdown 转换只改变文件格式与换行，不重建富文本排版。' : 'CSV 首行为字段名，空字段和数值均保留为字符串；JSON 仅接受扁平对象数组，null 与缺失值导出为空单元格。').fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(20).width('100%')
            } else {
              ForEach(this.selected, (file: WorkspaceFile, index: number) => {
                Row({ space: 10 }) {
                  Text((index + 1).toString().padStart(2,'0')).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand')).width(26)
                  Column({ space: 3 }) { Text(file.name).fontSize(14).fontColor($r('app.color.text_primary')).maxLines(2); Text(FileService.sizeLabel(file.size)).fontSize(11).fontColor($r('app.color.text_secondary')); }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  Button() {
                    SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18).fontColor([$r('app.color.brand')])
                  }.id('file-move-up-' + file.id).width(34).height(34).padding(0).flexShrink(0)
                    .backgroundColor($r('app.color.brand_soft')).accessibilityText('上移文件')
                    .onClick(() => this.reorder(index,-1)).enabled(!this.busy && index > 0)
                  Button() {
                    SymbolGlyph($r('sys.symbol.xmark')).fontSize(18).fontColor([$r('app.color.text_secondary')])
                  }.id('file-remove-' + file.id).width(34).height(34).padding(0).flexShrink(0)
                    .backgroundColor($r('app.color.soft_surface')).accessibilityText('移除文件')
                    .onClick(() => { this.cleanThumbnails(); this.selected = this.selected.filter((entry: WorkspaceFile) => entry.id !== file.id); }).enabled(!this.busy)
                }.padding(14).width('100%').backgroundColor($r('app.color.surface')).borderRadius(16)
              }, (file: WorkspaceFile) => file.id)
              if (this.selected.length > 0 && !this.needsImage()) { Button('预览第一份 PDF').fontSize(13).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(() => this.preview(this.selected[0])).enabled(!this.busy) }
            }
            if (this.toolId === 'pdf-edit') { this.pdfOrganizer() }
            Column({ space: 14 }) {
              Text('处理设置').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              Column({ space: 7 }) {
                Text(this.usesOutputPrefix() ? '输出文件名前缀' : '输出文件名').id('file-result-name-label').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
                TextInput({text:this.name,placeholder:'留空使用“' + this.defaultOutputName() + '”'}).id('file-result-name').fontSize(14).maxLength(96).backgroundColor($r('app.color.soft_surface')).onChange((value:string) => { this.name = value; }).enabled(!this.busy)
                Text(this.outputNameHint()).id('file-result-name-hint').fontSize(11).lineHeight(18).fontColor($r('app.color.text_secondary')).width('100%')
              }.width('100%')
              if (this.toolId === 'image-compress') {
                Select([{ value: 'JPEG · 小巧通用' }, { value: 'WebP · 保留透明' }]).selected(this.format === 2 ? 1 : 0).value(this.format === 2 ? 'WebP · 保留透明' : 'JPEG · 小巧通用').onSelect((index: number) => { this.format = index === 1 ? 2 : 1; }).width('100%')
                TextInput({ text: this.targetWidth, placeholder: '最大宽度 / px，留空保持原宽度' }).id('image-compress-width').type(InputType.Number).onChange((text: string) => { this.targetWidth = text; })
                TextInput({ text: this.targetMB, placeholder: '每张目标大小 / MB，可留空，例如 0.5' }).id('image-compress-target').type(InputType.NUMBER_DECIMAL).onChange((text: string) => { this.targetMB = text; })
                Text('设置目标后会逐步降低质量和尺寸，优先保留更清晰的结果。未达目标会明确提示；不会保存比原图更大的副本。JPEG 不保留透明，透明图片请选择 WebP。仅处理静态图片。').fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%')
              }
              if (this.toolId === 'image-convert') {
                Select([{value:'PNG · 无损透明'},{value:'JPEG · 小巧通用'},{value:'WebP · 高效压缩'}]).selected(this.format).value(['PNG · 无损透明','JPEG · 小巧通用','WebP · 高效压缩'][this.format]).onSelect((index:number) => { this.format = index; }).width('100%')
                TextInput({text:this.targetWidth,placeholder:'输出宽度（px，可留空）'}).type(InputType.Number).fontSize(13).backgroundColor($r('app.color.soft_surface')).onChange((value:string) => { this.targetWidth = value; })
                Text('宽度最大 8192 px，留空保留原始尺寸。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
              }
              if ((this.needsImage() && this.toolId !== 'image-ocr') || this.toolId === 'pdf-compress') {
                Text('编码质量  ' + Math.round(this.quality).toString() + '%').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
                Slider({value:this.quality,min:1,max:100,step:1}).selectedColor($r('app.color.brand')).onChange((value:number) => { this.quality = value; }).width('100%')
                Text(this.toolId === 'images-pdf' ? '每张图片生成一张 A4 页面，等比居中。' : this.toolId === 'image-compress' ? '质量越低，文件通常越小。请预览清晰度后使用；重新编码不保证保留拍摄信息。' : '仅缩小、不放大；JPEG 不保留透明通道。HEIC 解码与 WebP 编码以设备支持为准。PNG 质量参数不影响无损输出。').fontSize(11).fontColor($r('app.color.text_secondary')).lineHeight(18)
              }
              if (this.toolId === 'pdf-compress') {
                TextInput({ text: this.targetMB, placeholder: '目标大小 / MB（可留空，例如 2）' }).id('pdf-target-mb').type(InputType.NUMBER_DECIMAL).onChange((text: string) => { this.targetMB = text; })
                Text('图像压缩会把每页转为图片，文字不再可选中，链接、批注和表单不再交互。请保留原件，并预览核对清晰度；目标大小受内容影响。').fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%')
              }
              if (['image-convert', 'image-compress', 'images-pdf', 'pdf-compress'].includes(this.toolId)) {
                if (this.toolId === 'image-convert') { Button('邮件图片：JPEG / 1280px / 75%').fontSize(12).onClick(() => { this.format = 1; this.targetWidth = '1280'; this.quality = 75; this.selectedPresetId = ''; this.presetName = '邮件图片'; }) }
                ForEach(this.presets.filter((entry: LumiFilePreset) => entry.tool === this.toolId), (preset: LumiFilePreset) => {
                  Button('预设 · ' + preset.name).fontSize(12).onClick(() => this.applyPreset(preset))
                }, (preset: LumiFilePreset) => preset.id)
                TextInput({ text: this.presetName, placeholder: '预设名称' }).maxLength(40).onChange((text: string) => { this.presetName = text; })
                Row({ space: 8 }) {
                  Button('保存预设').onClick(() => this.savePreset())
                  Button('另存预设').onClick(() => { this.selectedPresetId = ''; this.savePreset(); })
                  if (this.selectedPresetId) { Button('删除预设').onClick(() => this.deletePreset()) }
                }.width('100%')
              }
              if (['pdf-split','pdf-extract','pdf-images'].includes(this.toolId)) { TextInput({text:this.pages,placeholder:'页码，例如 1-3,5（留空选择全部）'}).fontSize(13).backgroundColor($r('app.color.soft_surface')).onChange((value:string) => { this.pages = value; }) }
              if (this.toolId.startsWith('pdf-')) { TextInput({text:this.password,placeholder:'PDF 密码（未加密可留空）'}).type(InputType.Password).fontSize(13).backgroundColor($r('app.color.soft_surface')).onChange((value:string) => { this.password = value; this.cleanThumbnails(); }) }
              if (this.toolId === 'pdf-merge') { Text('保留文字和矢量结构。含链接或批注的 PDF 会停止合并，以避免系统接口造成批注丢失。文件按上方顺序合并；合并输出默认未加密。').fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(20) }
              if (this.toolId === 'pdf-split') { Text('选中页面将各自保存为独立 PDF。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%') }
              if (this.toolId === 'text-convert') { Select([{value:'导出 Markdown (.md)'},{value:'导出纯文本 (.txt)'}]).selected(this.format).value(this.format===0?'导出 Markdown (.md)':'导出纯文本 (.txt)').onSelect((index:number) => { this.format=index; }).width('100%') }
            }.padding(18).backgroundColor($r('app.color.surface')).borderRadius(20).width('100%')
            Button(this.busy ? '正在处理…' : '开始' + (this.isText() ? '转换' : '处理')).width('100%').height(52).fontWeight(FontWeight.Bold).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.busy).onClick(() => this.run())
            if (this.busy) {
              Progress({value:this.progress,total:100,type:ProgressType.Linear}).color($r('app.color.brand')).width('100%')
              Button('取消任务').enabled(this.canCancel).fontSize(12).height(36).backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_secondary')).onClick(() => { if(this.currentTask){ try{taskpool.cancel(this.currentTask);this.canCancel=false;this.cancelRequested=true;this.message='正在取消，当前页面处理完成后停止…';}catch(error){this.fail(error as Error);} } })
            }
          }
          if (this.message) { Text(this.message).fontSize(13).fontColor(this.isError ? $r('app.color.error') : $r('app.color.success')).lineHeight(21).padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(14) }
          if (this.output) {
            this.sectionLabel('结果预览', '内容可选中复制，保存后可从工作区继续处理。')
            if (this.toolId === 'image-ocr') {
              Image(this.selected[0]?.path || '').width('100%').height(220).objectFit(ImageFit.Contain)
              TextArea({ text: this.output }).height(220).onChange((text: string) => { this.output = text; })
              Row({ space: 8 }) {
                Button('复制识别文字').id('ocr-copy').layoutWeight(1).height(42).fontSize(13).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(() => this.copyOcr())
                Button('沉淀到知萤笔记').id('ocr-share-lexinote').layoutWeight(1).height(42).fontSize(13).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(() => this.shareOcrToLexiNote())
              }.width('100%')
              if (/[A-Za-z]{3,}/.test(this.output)) {
                Row({ space: 8 }) {
                  Button('送入词萤伴读').id('ocr-send-lexiglow-article').layoutWeight(1).height(40).fontSize(12).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.sendOcrToLexiGlow(true))
                  Button('词萤提取生词').id('ocr-send-lexiglow-words').layoutWeight(1).height(40).fontSize(12).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.sendOcrToLexiGlow(false))
                }.width('100%')
              }
            }
            if (this.toolId !== 'image-ocr') {
            Text(this.output.slice(0,16000)).fontSize(12).fontFamily('monospace').fontColor($r('app.color.text_primary')).copyOption(CopyOptions.InApp).padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(16)
            }
            if (this.toolId !== 'image-ocr' && this.output.length > 16000) { Text('仅展示前 16,000 字符，导出包含完整结果。').fontSize(11).fontColor($r('app.color.text_secondary')) }
            Button('保存结果').width('100%').height(48).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(() => this.saveText())
          }
          ForEach(this.outputs, (file: WorkspaceFile) => { this.resultRow(file, false) }, (file: WorkspaceFile) => JSON.stringify(file))
          ForEach(this.previewRequests, (request: FilePreviewRequest) => {
            Column({ space: 12 }) {
              Row() {
                Text('文件预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).layoutWeight(1)
                Button('收起').id('file-preview-close').fontSize(12).backgroundColor($r('app.color.brand_soft'))
                  .fontColor($r('app.color.brand')).onClick(() => { this.previewNeedsScroll = false; this.previewRequests = []; })
              }.width('100%')
              FilePreview({ filePath: request.path, password: request.password })
            }.id('file-preview-panel').width('100%')
              .onAreaChange(() => {
                if (this.previewNeedsScroll) {
                  this.previewNeedsScroll = false;
                  this.pageScroller.scrollEdge(Edge.Bottom);
                }
              })
          }, (request: FilePreviewRequest) => request.id.toString())
        }.width('100%').padding({left:22,right:22,top:12,bottom:44 + this.bottomInset})
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
      const param = context.pathInfo.param as FileToolRouteParam;
      if (param) {
        this.initializeRoute(param);
      }
    })
    .onHidden(() => { this.persistSession().catch(() => {}); })
    .onBackPressed(() => { return this.blockBackWhileBusy(); })
    .backgroundColor($r('app.color.background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
