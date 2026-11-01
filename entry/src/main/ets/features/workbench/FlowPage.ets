import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { StorageService } from '../../core/StorageService';
import { TaskManager } from '../../core/TaskManager';
import { processFiles, ProcessingOptions } from '../files/FileProcessor';
import { preparePdfPages, LumiPdfPageEdit } from '../files/PdfEnhancements';
import { WorkbenchStore } from './WorkbenchStore';
import { LumiCollection, LumiFlowSession, LumiFlowRecipe, LumiSavedPage } from './WorkbenchModels';
import { LumiResultCard } from './ResultCard';

export class LumiFlowRoute { kind: string = 'materials'; flowId: string = ''; recipeId: string = ''; }
@Builder
export function lumiFlowBuilder() { LumiFlowPage() }
@Component
export struct LumiFlowPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State private session: LumiFlowSession = new LumiFlowSession();
  @State private files: WorkspaceFile[] = [];
  @State private pageEdits: LumiPdfPageEdit[] = [];
  @State private busy: boolean = false;
  @State private ready: boolean = false;
  @State private progress: number = 0;
  @State private feedback: string = '';
  @State private password: string = '';
  @State private recipeName: string = '';
  @State private showLibrary: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private currentTask: taskpool.Task | undefined = undefined;
  private cancelled: boolean = false;
  private thumbPrefix: string = '';
  private saveTimer: number = -1;
  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async init(param: LumiFlowRoute): Promise<void> {
    try {
      this.files = await FileService.list(this.ctx());
      const existing = param.flowId ? (await WorkbenchStore.flows()).find((flow: LumiFlowSession) => flow.id === param.flowId) : undefined;
      if (param.flowId && !existing) { throw new Error('此流程记录已移除，请返回首页重新开始'); }
      if (existing) { this.session = existing; this.feedback = existing.error || '已恢复上次的文件、顺序与设置；加密文件请重新输入密码。'; }
      else {
        const fresh = new LumiFlowSession(); fresh.id = WorkbenchStore.newId(); fresh.kind = param.kind;
        fresh.name = param.kind === 'screenshots' ? '截图合集' : '提交材料'; fresh.targetMB = param.kind === 'screenshots' ? '' : '5';
        if (param.recipeId) {
          const recipe = (await WorkbenchStore.recipes()).find((entry: LumiFlowRecipe) => entry.id === param.recipeId);
          if (recipe) { fresh.kind = recipe.kind; fresh.name = recipe.outputName; fresh.targetMB = recipe.targetMB; fresh.quality = recipe.quality; }
        }
        this.session = fresh;
      }
      this.ready = true;
      if (existing && this.session.stage === 1 && this.session.basePath) { this.busy = true; try { await this.loadPages(); } finally { this.busy = false; } }
    } catch (error) { this.feedback = (error as Error).message; }
  }
  private async save(): Promise<void> {
    if (!this.ready) { return; }
    this.session.updatedAt = Date.now();
    await WorkbenchStore.putFlow(this.session);
  }
  private changed(): void {
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); }
    this.saveTimer = setTimeout(() => { this.saveTimer = -1; this.save().catch((error: Error) => { this.feedback = error.message; }); }, 250);
  }
  aboutToDisappear(): void {
    if (this.saveTimer >= 0) { clearTimeout(this.saveTimer); }
    this.save().catch(() => {}); this.cleanThumbs();
  }
  private async leave(): Promise<void> {
    if (this.busy) { this.feedback = '处理期间请等待或取消当前步骤'; return; }
    try { await this.save(); this.pathStack.pop(); } catch (error) { this.feedback = (error as Error).message; }
  }
  private cleanThumbs(): void {
    if (this.thumbPrefix) { try { for (const name of fs.listFileSync(this.ctx().cacheDir)) { if (name.startsWith(this.thumbPrefix.split('/').pop() + '_')) { fs.unlinkSync(this.ctx().cacheDir + '/' + name); } } } catch (_) {} }
    this.thumbPrefix = ''; this.pageEdits = [];
  }
  private selectedFiles(): WorkspaceFile[] {
    const selected: WorkspaceFile[] = [];
    for (const path of this.session.inputs) { const file = this.files.find((entry: WorkspaceFile) => entry.path === path); if (file) { selected.push(file); } }
    return selected;
  }
  private invalidateInputs(): void {
    this.session.prepared = []; this.session.basePath = ''; this.session.organizedPath = ''; this.session.finalPath = ''; this.session.edits = [];
    this.cleanThumbs(); this.changed();
  }
  private addFiles(files: WorkspaceFile[]): void {
    const supported = files.filter((file: WorkspaceFile) => file.mime.startsWith('image/') || (this.session.kind === 'materials' && file.mime === 'application/pdf'));
    if (supported.length !== files.length) { this.feedback = '已跳过不支持的类型；此流程接收图片' + (this.session.kind === 'materials' ? '与 PDF' : ''); }
    this.session.inputs = this.session.inputs.concat(supported.map((file: WorkspaceFile) => file.path)).filter((path: string, index: number, all: string[]) => all.indexOf(path) === index).slice(0, 20);
    this.invalidateInputs(); this.showLibrary = false;
  }
  private async pick(): Promise<void> {
    this.busy = true;
    try { const picked = await FileService.pickFiles(this.ctx(), [this.session.kind === 'materials' ? '图片与 PDF|.pdf,.png,.jpg,.jpeg,.webp,.heic' : '图片|.png,.jpg,.jpeg,.webp,.heic'], 20); this.files = await FileService.list(this.ctx()); if (picked.length) { this.addFiles(picked); await this.save(); } }
    catch (error) { this.feedback = (error as Error).message; } finally { this.busy = false; }
  }
  private moveInput(index: number): void { const paths = this.session.inputs.slice(); paths.splice(index - 1, 0, paths.splice(index, 1)[0]); this.session.inputs = paths; this.invalidateInputs(); }
  private async collection(): Promise<void> {
    const group = new LumiCollection(); group.id = this.session.id; group.name = this.session.name.trim() || '我的材料'; group.createdAt = this.session.updatedAt || Date.now();
    await WorkbenchStore.putCollection(group);
  }
  private async operation(tool: string, inputs: string[], label: string, edits: LumiPdfPageEdit[] = []): Promise<string> {
    if (this.cancelled) { throw new Error('当前步骤已取消，可继续上次进度'); }
    inputs.forEach((path: string) => FileService.assertOwned(this.ctx(), path));
    const name = FileService.cleanName(this.session.name.trim() || '我的材料') + '_' + label + '.pdf';
    const output = FileService.outputPath(this.ctx(), name);
    const options: ProcessingOptions = { tool: tool, inputs: inputs.slice(), outputs: [output], pages: '', quality: this.session.quality, width: 0, format: 'image/jpeg', password: this.password,
      targetBytes: Number(this.session.targetMB) * 1024 * 1024, editPages: edits.map((page: LumiPdfPageEdit): LumiPdfPageEdit => ({ original: page.original, rotation: page.rotation, thumbnail: '' })) };
    const taskId = await TaskManager.begin(tool, this.session.name + ' · ' + label, inputs);
    try {
      await TaskManager.running(taskId); this.currentTask = new taskpool.Task(processFiles, options);
      this.currentTask.onReceiveData((value: number) => { this.progress = value; TaskManager.progress(taskId, value).catch(() => {}); });
      const paths = await taskpool.execute(this.currentTask) as string[];
      const file = await FileService.register(this.ctx(), paths[0], name); file.collectionId = this.session.id; file.sourcePaths = inputs.slice(); file.role = 'intermediate';
      await FileService.updateDetails(this.ctx(), file); await TaskManager.complete(taskId, paths);
      return file.path;
    } catch (error) { await TaskManager.fail(taskId, (error as Error).message || '步骤未完成', this.cancelled); throw new Error((error as Error).message || '步骤未完成'); }
    finally { this.currentTask = undefined; }
  }
  private async loadPages(): Promise<void> {
    this.cleanThumbs(); this.thumbPrefix = this.ctx().cacheDir + '/flow_' + WorkbenchStore.newId();
    const pages = await taskpool.execute(preparePdfPages, this.session.basePath, this.password, this.thumbPrefix) as LumiPdfPageEdit[];
    if (this.session.edits.length) {
      this.pageEdits = this.session.edits.map((saved: LumiSavedPage): LumiPdfPageEdit => ({ original: saved.original, rotation: saved.rotation, thumbnail: pages.find((page: LumiPdfPageEdit) => page.original === saved.original)?.thumbnail || '' }));
    } else { this.pageEdits = pages; this.rememberEdits(); }
  }
  private rememberEdits(): void {
    this.session.edits = this.pageEdits.map((page: LumiPdfPageEdit): LumiSavedPage => ({ original: page.original, rotation: page.rotation }));
    this.session.organizedPath = ''; this.session.finalPath = ''; this.changed();
  }
  private editPage(index: number, action: string): void {
    const pages = this.pageEdits.slice();
    if (action === 'up' && index > 0) { pages.splice(index - 1, 0, pages.splice(index, 1)[0]); }
    else if (action === 'remove' && pages.length > 1) { pages.splice(index, 1); }
    else if (action === 'rotate') { const page = pages[index]; pages[index] = { original: page.original, rotation: (page.rotation + 90) % 360, thumbnail: page.thumbnail }; }
    this.pageEdits = pages; this.rememberEdits();
  }
  private async advance(): Promise<void> {
    if (this.busy || !this.ready) { return; }
    if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) { this.feedback = '当前设备不支持系统 PDF 服务'; return; }
    this.busy = true; this.cancelled = false; this.feedback = ''; this.progress = 0;
    try {
      if (this.session.stage === 0 && !this.session.inputs.length) { throw new Error('请先选择文件'); }
      await this.collection();
      if (this.session.stage === 0) {
        if (!this.session.inputs.length) { throw new Error('请先选择文件'); }
        if (this.selectedFiles().length !== this.session.inputs.length) { throw new Error('部分原件已不可用，请移除缺失文件并重新选择'); }
        for (const source of this.selectedFiles()) {
          if (!source.collectionId) { source.collectionId = this.session.id; source.role = 'source'; await FileService.updateDetails(this.ctx(), source); }
        }
        await this.save();
        const prepared = this.session.prepared.slice();
        prepared.forEach((path: string) => FileService.assertOwned(this.ctx(), path));
        for (let index = prepared.length; index < this.session.inputs.length; index++) {
          const file = this.files.find((entry: WorkspaceFile) => entry.path === this.session.inputs[index]);
          if (!file) { throw new Error('文件不可用'); }
          prepared.push(file.mime === 'application/pdf' ? file.path : await this.operation('images-pdf', [file.path], '图片' + (index + 1).toString()));
          this.session.prepared = prepared.slice(); await this.save();
        }
        if (!this.session.basePath) { this.session.basePath = prepared.length === 1 ? prepared[0] : await this.operation('pdf-merge', prepared, '合并'); await this.save(); }
        if (this.cancelled) { throw new Error('当前步骤已取消，可继续上次进度'); }
        await this.loadPages(); this.session.stage = 1;
      } else if (this.session.stage === 1) {
        if (!this.pageEdits.length) { await this.loadPages(); }
        this.session.organizedPath = await this.operation('pdf-edit', [this.session.basePath], '整理', this.pageEdits);
        this.session.stage = 2;
      } else if (this.session.stage === 2) {
        if (this.session.targetMB && (!Number.isFinite(Number(this.session.targetMB)) || Number(this.session.targetMB) <= 0 || Number(this.session.targetMB) > 100)) { throw new Error('目标大小请输入 0–100 MB 之间的数值，或留空'); }
        const source = (await FileService.list(this.ctx())).find((file: WorkspaceFile) => file.path === this.session.organizedPath);
        if (!source) { throw new Error('整理结果不可用，请返回上一步重新整理'); }
        let finalPath = source.path;
        if (this.session.targetMB && source.size > Number(this.session.targetMB) * 1024 * 1024) { finalPath = await this.operation('pdf-compress', [source.path], '压缩'); }
        const final = (await FileService.list(this.ctx())).find((file: WorkspaceFile) => file.path === finalPath);
        if (!final) { throw new Error('结果无法读取'); }
        if (this.session.targetMB && final.size > Number(this.session.targetMB) * 1024 * 1024) {
          this.feedback = '当前结果 ' + FileService.sizeLabel(final.size) + '，尚未达到目标。已保留中间结果；请调低质量或调整目标后重试。';
        } else {
          final.name = FileService.cleanName(this.session.name.trim() || '我的材料').replace(/\.pdf$/i, '') + '.pdf'; final.role = 'final'; final.sourcePaths = this.session.inputs.slice(); final.collectionId = this.session.id; final.pageCount = this.session.edits.length;
          await FileService.updateDetails(this.ctx(), final); this.session.finalPath = final.path; this.session.stage = 3;
          await StorageService.addHistory('workflow', this.session.name, '材料已核对大小 · ' + this.session.edits.length.toString() + ' 页', final.path);
        }
      }
      this.session.error = ''; await this.save(); this.files = await FileService.list(this.ctx());
    } catch (error) { this.feedback = (error as Error).message || '步骤未完成'; this.session.error = this.feedback; try { await this.save(); } catch (_) { this.feedback += '；进度未能保存'; } }
    finally { this.busy = false; }
  }
  private async previous(): Promise<void> {
    if (this.busy) { return; }
    this.session.stage = Math.max(0, this.session.stage - 1); this.feedback = '';
    if (this.session.stage === 1 && !this.pageEdits.length) { this.busy = true; try { await this.loadPages(); } catch (error) { this.feedback = (error as Error).message; } finally { this.busy = false; } }
    await this.save();
  }
  private async saveRecipe(): Promise<void> {
    try {
      const recipe = new LumiFlowRecipe(); recipe.id = WorkbenchStore.newId(); recipe.name = this.recipeName.trim(); recipe.kind = this.session.kind;
      recipe.targetMB = this.session.targetMB; recipe.quality = this.session.quality; recipe.outputName = this.session.name.trim() || '我的材料';
      await WorkbenchStore.putRecipe(recipe); this.feedback = '流程已保存到首页，下次选择新文件即可复用。';
    } catch (error) { this.feedback = (error as Error).message; }
  }
  private async refreshFiles(): Promise<void> { this.files = await FileService.list(this.ctx()); }
  @Builder
  private titleBar() { LumiBackHeader({ title: this.session.kind === 'screenshots' ? '截图整理成 PDF' : '提交材料', onBack: () => { this.leave(); } }) }
  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 18 }) {
          Text('小事，一次办好').fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
          Text(['01 选择材料', '02 整理页面', '03 文件大小', '04 核对与分享'][this.session.stage]).fontSize(16).fontColor($r('app.color.brand')).width('100%')
          Progress({ value: this.session.stage + 1, total: 4, type: ProgressType.Linear }).color($r('app.color.brand')).width('100%')
          if (this.session.stage === 0) {
            Text('按下方顺序整理，支持最多 20 个文件。原件始终保留。').fontSize(13).fontColor($r('app.color.text_secondary'))
            Row({ space: 8 }) { Button('导入文件').id('flow-pick').layoutWeight(1).onClick(() => this.pick()); Button('从工作区选择').layoutWeight(1).onClick(() => { this.showLibrary = !this.showLibrary; }) }.enabled(!this.busy && this.ready)
            if (this.showLibrary) {
              ForEach(this.files.filter((file: WorkspaceFile) => file.mime.startsWith('image/') || (this.session.kind === 'materials' && file.mime === 'application/pdf')).slice(0, 100), (file: WorkspaceFile) => {
                Button(file.name, { buttonStyle: ButtonStyleMode.TEXTUAL }).width('100%').onClick(() => this.addFiles([file])).enabled(!this.busy)
              }, (file: WorkspaceFile) => file.id)
            }
            ForEach(this.session.inputs, (path: string, index: number) => {
              Row({ space: 8 }) {
                Text((index + 1).toString() + '. ' + (this.files.find((file: WorkspaceFile) => file.path === path)?.name || '文件缺失')).layoutWeight(1).fontSize(14).fontColor($r('app.color.text_primary'))
                Button('上移').fontSize(12).enabled(index > 0 && !this.busy).onClick(() => this.moveInput(index))
                Button('移除').fontSize(12).enabled(!this.busy).onClick(() => { this.session.inputs = this.session.inputs.filter((item: string) => item !== path); this.invalidateInputs(); })
              }.padding(12).width('100%').backgroundColor($r('app.color.surface')).borderRadius(16)
            }, (path: string) => path)
            TextInput({ text: this.session.name, placeholder: '材料名称，也用作结果文件名' }).id('flow-name').maxLength(80).onChange((text: string) => { this.session.name = text; this.changed(); }).enabled(!this.busy)
          }
          if (this.session.stage === 1) {
            Text('调整顺序、旋转或删除多余页面。').fontSize(13).fontColor($r('app.color.text_secondary'))
            ForEach(this.pageEdits, (page: LumiPdfPageEdit, index: number) => {
              Row({ space: 12 }) {
                Image(fileUri.getUriFromPath(page.thumbnail)).width(70).height(95).objectFit(ImageFit.Contain).rotate({ angle: page.rotation })
                Column({ space: 8 }) {
                  Text('第 ' + (index + 1).toString() + ' 页').fontColor($r('app.color.text_primary'))
                  Row({ space: 6 }) {
                    Button('上移').fontSize(12).enabled(index > 0 && !this.busy).onClick(() => this.editPage(index, 'up'))
                    Button('旋转').fontSize(12).enabled(!this.busy).onClick(() => this.editPage(index, 'rotate'))
                    Button('删除').fontSize(12).enabled(this.pageEdits.length > 1 && !this.busy).onClick(() => this.editPage(index, 'remove'))
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').padding(12).backgroundColor($r('app.color.surface')).borderRadius(16)
            }, (page: LumiPdfPageEdit) => page.original.toString() + '_' + page.rotation.toString())
          }
          if (this.session.stage === 2) {
            TextInput({ text: this.session.targetMB, placeholder: '目标大小 / MB，留空保留整理结果' }).id('flow-target').type(InputType.NUMBER_DECIMAL).onChange((text: string) => { this.session.targetMB = text; this.changed(); }).enabled(!this.busy)
            Text('压缩质量 ' + this.session.quality.toString() + '%').fontColor($r('app.color.text_primary'))
            Slider({ value: this.session.quality, min: 1, max: 100, step: 1 }).onChange((value: number) => { this.session.quality = Math.round(value); this.changed(); }).enabled(!this.busy)
            Text('文件超过目标时才进行图像压缩：文字将不再可选择，链接、批注与表单不再交互，输出未加密。完成后请预览清晰度。留空可保留整理后的文档结构。').fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary'))
          }
          if (this.session.stage < 3) {
            TextInput({ text: this.password, placeholder: '加密 PDF 密码（仅本次使用，不保存）' }).type(InputType.Password).onChange((text: string) => { this.password = text; }).enabled(!this.busy)
            Button(this.busy ? '正在处理…' : ['生成待整理文档', '保存页面，设置大小', '生成最终成果'][this.session.stage]).id('flow-next').height(50).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.busy && this.ready).onClick(() => this.advance())
          } else {
            Text('已完成大小检查，请预览内容后分享。原件与过程文件可在资料集合中查看。').fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary'))
            if (!this.files.some((file: WorkspaceFile) => file.path === this.session.finalPath)) { Text('结果已移入回收站或移除，请返回工作区查看。').fontSize(13).fontColor($r('app.color.text_secondary')) }
            ForEach(this.files.filter((file: WorkspaceFile) => file.path === this.session.finalPath), (file: WorkspaceFile) => { LumiResultCard({ file: file, allowContinue: false, onChanged: () => { this.refreshFiles(); } }) }, (file: WorkspaceFile) => JSON.stringify(file))
            TextInput({ text: this.recipeName, placeholder: '流程名称，例如每周材料提交' }).id('flow-recipe-name').maxLength(40).onChange((text: string) => { this.recipeName = text; })
            Button('保存流程，下次照做').id('flow-save-recipe').onClick(() => this.saveRecipe())
          }
          if (this.busy) {
            Progress({ value: this.progress, total: 100, type: ProgressType.Linear }).width('100%')
            Button('取消当前步骤').onClick(() => { this.cancelled = true; if (this.currentTask) { try { taskpool.cancel(this.currentTask); } catch (_) {} } })
          }
          if (this.feedback) { Text(this.feedback).fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%') }
          if (this.session.stage > 0 && this.session.stage < 3) { Button('返回上一步', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy).onClick(() => this.previous()) }
          Button('保存并返回首页', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy).onClick(() => this.leave())
        }.width('100%').padding({ left: 22, right: 22, top: 18, bottom: 44 + this.bottomInset })
      }.width('100%').height('100%').contentStartOffset(56).scrollBar(BarState.Off).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.hideBackButton(true).title({ builder: () => { this.titleBar(); }, height: 56 }, { barStyle: BarStyle.STACK, scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR } })
      .onReady((context: NavDestinationContext) => { this.pathStack = context.pathStack; this.init((context.pathInfo.param as LumiFlowRoute) || new LumiFlowRoute()); })
      .onHidden(() => { this.save().catch(() => {}); })
      .onBackPressed(() => { this.leave(); return true; }).backgroundColor($r('app.color.background')).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
