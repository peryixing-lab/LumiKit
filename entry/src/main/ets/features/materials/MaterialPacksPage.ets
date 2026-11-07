import { common } from '@kit.AbilityKit';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { LumiHelpNavigation } from '../help/HelpNavigation';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { BatchFileService } from '../../core/BatchFileService';
import { FileToolRouteParam } from '../files/FileToolsPage';
import { LumiFlowRoute } from '../workbench/FlowPage';
import { FilePreview } from '../files/FilePreview';
import { LumiMaterialItem, LumiMaterialPack, LumiMaterialTemplate, LUMI_MATERIAL_FORMATS,
  LUMI_MATERIAL_FORMAT_LABELS, materialItemStatus, materialTemplateFromPack } from './MaterialPackModels';
import { LumiMaterialPackStore } from './MaterialPackStore';

export class LumiMaterialPackRoute { packId: string = ''; }

@Builder
export function lumiMaterialPacksBuilder() { LumiMaterialPacksPage() }

@Component
export struct LumiMaterialPacksPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State private packs: LumiMaterialPack[] = [];
  @State private templates: LumiMaterialTemplate[] = [];
  @State private files: WorkspaceFile[] = [];
  @State private current: LumiMaterialPack = new LumiMaterialPack();
  @State private nameDraft: string = '';
  @State private templateId: string = '';
  @State private templateName: string = '';
  @State private editingItemId: string = '';
  @State private itemName: string = '';
  @State private itemFormat: string = 'any';
  @State private itemLimit: string = '';
  @State private bindingItemId: string = '';
  @State private libraryQuery: string = '';
  @State private editingRequirements: boolean = false;
  @State private previewItemId: string = '';
  @State private busy: boolean = false;
  @State private initialized: boolean = false;
  @State private feedback: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private fail(error: Error): void { this.feedback = error.message || '操作未完成，请重试'; }
  private snapshot(): LumiMaterialPack { return JSON.parse(JSON.stringify(this.current)) as LumiMaterialPack; }

  private async refresh(): Promise<void> {
    this.files = (await FileService.list(this.ctx())).filter((file: WorkspaceFile): boolean => !file.name.toLowerCase().endsWith('.lumibak'));
    this.packs = await LumiMaterialPackStore.packs();
    this.templates = await LumiMaterialPackStore.templates();
  }

  private async initialize(param: LumiMaterialPackRoute): Promise<void> {
    try {
      await this.refresh(); this.initialized = true;
      if (param.packId) {
        const pack = this.packs.find((entry: LumiMaterialPack): boolean => entry.id === param.packId);
        if (pack) { this.openPack(pack); } else { this.feedback = '这份材料包已移除，可以重新创建清单。'; }
      }
    } catch (error) { this.fail(error as Error); }
  }

  private openPack(pack: LumiMaterialPack): void {
    this.current = JSON.parse(JSON.stringify(pack)) as LumiMaterialPack;
    this.nameDraft = pack.name; this.templateName = pack.name; this.feedback = '';
    this.bindingItemId = ''; this.editingRequirements = false;
  }

  private async persist(pack: LumiMaterialPack): Promise<void> {
    pack.updatedAt = Date.now();
    await LumiMaterialPackStore.putPack(pack);
    this.current = pack;
    this.packs = await LumiMaterialPackStore.packs();
  }

  private async createPack(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const pack = new LumiMaterialPack(); pack.id = LumiMaterialPackStore.newId();
      pack.name = this.nameDraft.trim() || '我的材料包'; pack.createdAt = Date.now(); pack.updatedAt = pack.createdAt;
      const template = this.templates.find((entry: LumiMaterialTemplate): boolean => entry.id === this.templateId);
      if (template) {
        pack.items = template.items.map((item: LumiMaterialItem): LumiMaterialItem => ({
          id: LumiMaterialPackStore.newId(), name: item.name, format: item.format, maxMB: item.maxMB, path: ''
        }));
      }
      await this.persist(pack); this.openPack(pack);
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }

  private async renamePack(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { const pack = this.snapshot(); pack.name = this.nameDraft.trim(); await this.persist(pack); this.feedback = '材料包名称已保存'; }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }

  private editRequirements(itemId: string = ''): void {
    const item = this.current.items.find((entry: LumiMaterialItem): boolean => entry.id === itemId);
    this.editingItemId = itemId; this.itemName = item?.name || ''; this.itemFormat = item?.format || 'any';
    this.itemLimit = item?.maxMB || ''; this.bindingItemId = ''; this.editingRequirements = true; this.feedback = '';
  }

  private async saveRequirements(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const pack = this.snapshot();
      let item = pack.items.find((entry: LumiMaterialItem): boolean => entry.id === this.editingItemId);
      if (!item) { item = new LumiMaterialItem(); item.id = LumiMaterialPackStore.newId(); pack.items.push(item); }
      item.name = this.itemName.trim(); item.format = this.itemFormat; item.maxMB = this.itemLimit.trim();
      await this.persist(pack); this.editingRequirements = false; this.feedback = '材料要求已保存';
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }

  private async bindFile(itemId: string, path: string): Promise<void> {
    const pack = this.snapshot();
    const item = pack.items.find((entry: LumiMaterialItem): boolean => entry.id === itemId);
    if (!item) { throw new Error('这项材料已移除'); }
    if (path) {
      const file = this.files.find((entry: WorkspaceFile): boolean => entry.path === path);
      if (!file) { throw new Error('文件已移除，请刷新后重新选择'); }
      FileService.assertOwned(this.ctx(), path);
      if (pack.items.some((entry: LumiMaterialItem): boolean => entry.id !== itemId && entry.path === path)) {
        throw new Error('此文件已经用于清单的另一项，请核对每项材料');
      }
    }
    item.path = path; await this.persist(pack); this.bindingItemId = '';
    this.feedback = path ? '文件已关联，请核对格式和大小状态。' : '已解除关联，原文件仍在工作区。';
  }

  private async chooseFile(itemId: string, path: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { await this.bindFile(itemId, path); } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }

  private async importFile(itemId: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const files = await FileService.pickFiles(this.ctx(), [], 1);
      await this.refresh();
      if (files.length && !files[0].name.toLowerCase().endsWith('.lumibak')) { await this.bindFile(itemId, files[0].path); }
      else if (files.length) { this.feedback = '备份包请在“我的”中恢复，不能作为材料提交。'; }
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }

  private fileFor(item: LumiMaterialItem): WorkspaceFile | undefined {
    return this.files.find((file: WorkspaceFile): boolean => file.path === item.path);
  }
  private status(item: LumiMaterialItem): string {
    const file = this.fileFor(item);
    return materialItemStatus(item, file?.name || '', file?.size ?? -1);
  }
  private readyCount(pack: LumiMaterialPack): number {
    return pack.items.filter((item: LumiMaterialItem): boolean => this.status(item) === '已准备').length;
  }
  private allReady(): boolean { return this.current.items.length > 0 && this.readyCount(this.current) === this.current.items.length; }
  private requirements(item: LumiMaterialItem): string {
    return LUMI_MATERIAL_FORMAT_LABELS[LUMI_MATERIAL_FORMATS.indexOf(item.format)] +
      (item.maxMB ? ' · 每份 ≤ ' + item.maxMB + ' MB' : ' · 不限大小要求');
  }
  private fileLabel(item: LumiMaterialItem): string {
    const file = this.fileFor(item);
    return file ? file.name + ' · ' + FileService.sizeLabel(file.size) : item.path ? '关联文件已不可用，请重新选择' : '尚未关联文件';
  }
  private formatOptions(): SelectOption[] { return LUMI_MATERIAL_FORMAT_LABELS.map((label: string): SelectOption => ({ value: label })); }
  private templateOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '空白清单' }];
    return options.concat(this.templates.map((template: LumiMaterialTemplate): SelectOption => ({ value: template.name })));
  }
  private visibleFiles(): WorkspaceFile[] {
    const query = this.libraryQuery.trim().toLowerCase();
    return this.files.filter((file: WorkspaceFile): boolean =>
      (file.name + ' ' + (file.tags || []).join(' ')).toLowerCase().includes(query));
  }

  private async removeItem(id: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { const pack = this.snapshot(); pack.items = pack.items.filter((item: LumiMaterialItem): boolean => item.id !== id); await this.persist(pack); this.feedback = '已移除清单项，文件保留。'; }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async deletePack(): Promise<void> {
    if (this.busy) { return; }
    const choice = await this.getUIContext().getPromptAction().showDialog({ title: '移除材料包？', message: '只移除清单与文件关联，所有原件和成果仍保留在工作区。', buttons: [{ text: '取消', color: '#64748B' }, { text: '移除清单', color: '#2864DA' }] });
    if (choice.index !== 1) { return; } this.busy = true;
    try { await LumiMaterialPackStore.deletePack(this.current.id); this.current = new LumiMaterialPack(); this.nameDraft = ''; await this.refresh(); this.feedback = '清单已移除，文件保留。'; }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async saveTemplate(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const template = materialTemplateFromPack(this.current, LumiMaterialPackStore.newId(), this.templateName || this.current.name);
      await LumiMaterialPackStore.putTemplate(template); this.templates = await LumiMaterialPackStore.templates();
      this.feedback = '模板已保存；下次新建时可复用要求，不会带入本次文件。';
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async deleteTemplate(id: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { await LumiMaterialPackStore.deleteTemplate(id); if (this.templateId === id) { this.templateId = ''; } this.templates = await LumiMaterialPackStore.templates(); }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }

  private processItem(item: LumiMaterialItem): void {
    const file = this.fileFor(item); if (!file) { return; }
    const param = new FileToolRouteParam(); param.filePath = file.path;
    const imageRequirement = ['image', 'jpeg', 'png', 'webp'].includes(item.format);
    param.toolId = file.mime === 'application/pdf' ? (imageRequirement ? 'pdf-images' : 'pdf-compress') : file.mime.startsWith('image/') ?
      (item.format === 'pdf' ? 'images-pdf' : this.status(item) === '超出大小' ? 'image-compress' : 'image-convert') : 'file-workspace';
    this.feedback = param.toolId === 'pdf-images' ? '先导出 PNG 页面；如需 JPEG 或 WebP，可继续转换。完成后返回清单选择新成果。' : '处理完成后，请返回清单选择新成果，原件继续保留。';
    this.pathStack.pushPathByName('fileTool', param);
  }
  private canProcess(item: LumiMaterialItem): boolean { const file = this.fileFor(item); return !!file && (file.mime === 'application/pdf' || file.mime.startsWith('image/')); }
  private deliveryFiles(): WorkspaceFile[] {
    return this.current.items.map((item: LumiMaterialItem): WorkspaceFile => {
      const file = this.fileFor(item) as WorkspaceFile;
      const named = JSON.parse(JSON.stringify(file)) as WorkspaceFile;
      const dot = file.name.lastIndexOf('.');
      const extension = dot > 0 ? file.name.substring(dot) : '';
      const stem = FileService.cleanName(item.name);
      named.name = extension && !stem.toLowerCase().endsWith(extension.toLowerCase()) ? stem + extension : stem;
      return named;
    });
  }
  private canMerge(): boolean {
    return this.allReady() && this.deliveryFiles().every((file: WorkspaceFile): boolean => file.mime === 'application/pdf' || file.mime.startsWith('image/'));
  }
  private async check(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try { await this.refresh(); this.feedback = this.allReady() ? '每项材料的格式和大小均符合清单要求。请预览核对内容后交付。' : '已重新检查：' + this.readyCount(this.current).toString() + '/' + this.current.items.length.toString() + ' 项已准备，请补齐或调整其余材料。'; }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async deliver(kind: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      await this.refresh();
      if (!this.allReady()) { throw new Error('尚有缺少或不符合要求的材料，请先补齐并核对后交付。'); }
      const files = this.deliveryFiles(); files.forEach((file: WorkspaceFile): void => FileService.assertOwned(this.ctx(), file.path));
      if (kind === 'share') { await BatchFileService.share(this.ctx(), files); this.feedback = '已打开系统分享，请选择接收应用。'; }
      else if (kind === 'export') { await BatchFileService.exportFiles(this.ctx(), files); this.feedback = '材料已导出，工作区原件保留。'; }
      else if (kind === 'zip') {
        const archive = await BatchFileService.archive(this.ctx(), files, this.current.name + '.zip');
        await FileService.exportFile(this.ctx(), archive.path, archive.name); this.feedback = '材料 ZIP 已导出，工作区保留副本。';
      } else if (kind === 'merge') {
        if (!this.canMerge()) { throw new Error('合并 PDF 仅支持已准备好的图片与 PDF 材料'); }
        const param = new LumiFlowRoute(); param.kind = 'materials'; param.filePaths = files.map((file: WorkspaceFile): string => file.path); param.outputName = this.current.name;
        this.pathStack.pushPathByName('workflow', param);
      }
    } catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private async shareOne(item: LumiMaterialItem): Promise<void> {
    const file = this.fileFor(item); if (!file || this.busy) { return; } this.busy = true;
    try { await FileService.share(this.ctx(), file.path, file.name); }
    catch (error) { this.fail(error as Error); } finally { this.busy = false; }
  }
  private leave(): void {
    if (this.busy) { this.feedback = '请等待当前操作结束'; return; }
    if (this.bindingItemId) { this.bindingItemId = ''; return; }
    if (this.editingRequirements) { this.editingRequirements = false; return; }
    if (this.current.id) { this.current = new LumiMaterialPack(); this.nameDraft = ''; this.feedback = ''; return; }
    this.pathStack.pop();
  }

  @Builder
  private titleBar() {
    LumiBackHeader({ title: this.current.id ? '材料清单' : '我的材料包', showTutorial: true, tutorialEnabled: !this.busy,
      onBack: () => { this.leave(); }, onTutorial: () => { LumiHelpNavigation.open(this.pathStack, 'material-packs'); } })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
          if (!this.initialized) {
            Button('重新读取材料包').onClick(() => { this.initialize(new LumiMaterialPackRoute()); })
          } else if (!this.current.id) {
            Text('备齐一件事需要的材料').fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Text('按自己的要求检查缺项、格式与大小，多份文件一起交付。').fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%')
            TextInput({ text: this.nameDraft, placeholder: '材料包名称，例如报名材料' }).id('material-pack-name').maxLength(80).onChange((text: string) => { this.nameDraft = text; }).enabled(!this.busy)
            Select(this.templateOptions()).value(this.templates.find((template: LumiMaterialTemplate): boolean => template.id === this.templateId)?.name || '空白清单').onSelect((index: number) => { this.templateId = index > 0 ? this.templates[index - 1].id : ''; }).enabled(!this.busy)
            Button('新建材料包').id('material-pack-create').height(48).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.busy).onClick(() => { this.createPack(); })
            if (!this.packs.length) { Text('先创建一份清单，再逐项关联已有文件或导入材料。').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%') }
            ForEach(this.packs, (pack: LumiMaterialPack) => {
              Button({ type: ButtonType.Normal }) {
                Column({ space: 7 }) {
                  Text(pack.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
                  Text(this.readyCount(pack).toString() + '/' + pack.items.length.toString() + ' 项已准备').fontSize(13).fontColor($r('app.color.text_secondary'))
                }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
              }.id('material-pack-' + pack.id).padding(0).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20).enabled(!this.busy).onClick(() => { this.openPack(pack); })
            }, (pack: LumiMaterialPack): string => JSON.stringify(pack))
            if (this.templates.length) {
              Text('我的清单模板').fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              ForEach(this.templates, (template: LumiMaterialTemplate) => {
                Row({ space: 12 }) {
                  Text(template.name + ' · ' + template.items.length.toString() + ' 项').fontSize(13).layoutWeight(1).fontColor($r('app.color.text_secondary'))
                  Button('移除模板', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).onClick(() => { this.deleteTemplate(template.id); }).enabled(!this.busy)
                }.width('100%')
              }, (template: LumiMaterialTemplate): string => template.id)
            }
          } else if (this.bindingItemId) {
            Text('选择要关联的材料').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Text('关联工作区副本；替换关联不会修改或删除原文件。').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
            TextInput({ text: this.libraryQuery, placeholder: '搜索文件名或标签' }).id('material-file-search').onChange((text: string) => { this.libraryQuery = text; })
            Button('导入一个新文件').id('material-import-file').width('100%').enabled(!this.busy).onClick(() => { this.importFile(this.bindingItemId); })
            if (!this.visibleFiles().length) { Text('没有符合条件的文件，可以导入新文件。').fontColor($r('app.color.text_secondary')) }
            ForEach(this.visibleFiles(), (file: WorkspaceFile) => {
              Button(file.name + ' · ' + FileService.sizeLabel(file.size)).id('material-bind-' + file.id).width('100%').fontSize(13).fontColor($r('app.color.brand')).backgroundColor($r('app.color.surface')).enabled(!this.busy).onClick(() => { this.chooseFile(this.bindingItemId, file.path); })
            }, (file: WorkspaceFile): string => file.path)
            Button('返回清单', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { this.bindingItemId = ''; })
          } else if (this.editingRequirements) {
            Text(this.editingItemId ? '修改材料要求' : '添加一项材料').fontSize(23).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            TextInput({ text: this.itemName, placeholder: '材料名称，例如申请表' }).id('material-item-name').maxLength(80).onChange((text: string) => { this.itemName = text; }).enabled(!this.busy)
            Select(this.formatOptions()).value(LUMI_MATERIAL_FORMAT_LABELS[LUMI_MATERIAL_FORMATS.indexOf(this.itemFormat)]).onSelect((index: number) => { this.itemFormat = LUMI_MATERIAL_FORMATS[index]; }).enabled(!this.busy)
            TextInput({ text: this.itemLimit, placeholder: '每份大小上限（MB），留空不限' }).id('material-item-limit').type(InputType.NUMBER_DECIMAL).maxLength(16).onChange((text: string) => { this.itemLimit = text; }).enabled(!this.busy)
            Text('大小要求填写 0–100 MB 之间的正数，例如 0.5。请按接收方实际要求设置。').fontSize(12).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
            Button('保存材料要求').id('material-item-save').width('100%').height(48).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.busy).onClick(() => { this.saveRequirements(); })
            Button('取消编辑', { buttonStyle: ButtonStyleMode.TEXTUAL }).enabled(!this.busy).onClick(() => { this.editingRequirements = false; })
          } else {
            TextInput({ text: this.nameDraft, placeholder: '材料包名称' }).id('material-pack-rename').maxLength(80).onChange((text: string) => { this.nameDraft = text; }).enabled(!this.busy)
            Button('保存名称', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { this.renamePack(); }).enabled(!this.busy)
            Text(this.readyCount(this.current).toString() + '/' + this.current.items.length.toString() + ' 项已准备').id('material-pack-status').fontSize(23).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            Button('重新检查材料').id('material-pack-check').width('100%').enabled(!this.busy).onClick(() => { this.check(); })
            ForEach(this.current.items, (item: LumiMaterialItem) => {
              Column({ space: 10 }) {
                Row({ space: 12 }) {
                  Text(item.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
                  Text(this.status(item)).id('material-status-' + item.id).fontSize(12).fontColor(this.status(item) === '已准备' ? $r('app.color.success') : $r('app.color.error'))
                }.width('100%')
                Text(this.requirements(item)).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
                Text(this.fileLabel(item)).fontSize(13).lineHeight(21).fontColor($r('app.color.text_primary')).width('100%')
                Row({ space: 8 }) {
                  Button(item.path ? '更换文件' : '选择文件').id('material-choose-' + item.id).fontSize(12).onClick(() => { this.bindingItemId = item.id; this.libraryQuery = ''; })
                  Button('修改要求').fontSize(12).onClick(() => { this.editRequirements(item.id); })
                  if (this.canProcess(item)) { Button('处理文件').fontSize(12).onClick(() => { this.processItem(item); }) }
                }.width('100%').enabled(!this.busy)
                if (item.path) {
                  Row({ space: 8 }) {
                    if (this.canProcess(item)) { Button('预览', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).enabled(!this.busy).onClick(() => { this.previewItemId = this.previewItemId === item.id ? '' : item.id; }) }
                    Button('单份分享', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).enabled(!this.busy && !!this.fileFor(item)).onClick(() => { this.shareOne(item); })
                    Button('解除关联', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).enabled(!this.busy).onClick(() => { this.chooseFile(item.id, ''); })
                  }.width('100%')
                }
                if (this.previewItemId === item.id && this.canProcess(item)) { FilePreview({ filePath: this.fileFor(item)?.path || '' }) }
                Button('移除清单项', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).fontColor($r('app.color.text_secondary')).enabled(!this.busy).onClick(() => { this.removeItem(item.id); })
              }.width('100%').padding(18).backgroundColor($r('app.color.surface')).borderRadius(20)
            }, (item: LumiMaterialItem): string => JSON.stringify(item))
            Button('添加材料要求').id('material-item-add').width('100%').enabled(!this.busy && this.current.items.length < 20).onClick(() => { this.editRequirements(); })
            Text('交付前请预览确认内容。全部材料符合清单的格式与大小要求后，可一次导出或分享。').fontSize(12).lineHeight(21).fontColor($r('app.color.text_secondary')).width('100%')
            Row({ space: 10 }) {
              Button('全部导出').id('material-export').layoutWeight(1).onClick(() => { this.deliver('export'); })
              Button('全部分享').id('material-share').layoutWeight(1).onClick(() => { this.deliver('share'); })
            }.width('100%').enabled(!this.busy && this.allReady())
            Row({ space: 10 }) {
              Button('导出 ZIP').id('material-zip').layoutWeight(1).enabled(!this.busy && this.allReady()).onClick(() => { this.deliver('zip'); })
              Button('合并成 PDF').id('material-merge').layoutWeight(1).enabled(!this.busy && this.canMerge()).onClick(() => { this.deliver('merge'); })
            }.width('100%')
            TextInput({ text: this.templateName, placeholder: '清单模板名称' }).id('material-template-name').maxLength(80).onChange((text: string) => { this.templateName = text; }).enabled(!this.busy)
            Button('保存为清单模板').id('material-template-save').width('100%').enabled(!this.busy && this.current.items.length > 0).onClick(() => { this.saveTemplate(); })
            Text('模板仅保存材料名称和要求，不带入本次关联的文件。').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
            Button('移除材料包', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontColor($r('app.color.text_secondary')).enabled(!this.busy).onClick(() => { this.deletePack(); })
          }
          if (this.busy) { Text('正在处理，请稍候…').fontSize(13).fontColor($r('app.color.brand')).width('100%') }
          if (this.feedback) { Text(this.feedback).id('material-feedback').fontSize(13).lineHeight(22).fontColor($r('app.color.text_secondary')).width('100%') }
        }.width('100%').padding({ left: 22, right: 22, top: 18, bottom: 36 + this.bottomInset })
      }.width('100%').height('100%').contentStartOffset(56).scrollBar(BarState.Off).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }.hideBackButton(true).title({ builder: () => { this.titleBar(); }, height: 56 }, { barStyle: BarStyle.STACK, scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR } })
      .onReady((context: NavDestinationContext) => { this.pathStack = context.pathStack; this.initialize((context.pathInfo.param as LumiMaterialPackRoute) || new LumiMaterialPackRoute()); })
      .onShown(() => { if (this.initialized) { this.refresh().catch((error: Error) => { this.fail(error); }); } })
      .onBackPressed(() => { this.leave(); return true; }).backgroundColor($r('app.color.background')).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
