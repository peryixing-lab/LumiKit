import { common } from '@kit.AbilityKit';
import { taskpool } from '@kit.ArkTS';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { FilePreview } from '../files/FilePreview';
import { WorkbenchStore } from './WorkbenchStore';
import { LumiCollection } from './WorkbenchModels';
import { inspectResult, LumiResultInfo } from './ResultInfo';

@Component
export struct LumiResultCard {
  @Prop file: WorkspaceFile;
  @Prop selecting: boolean = false;
  @Prop selectionChecked: boolean = false;
  selectable: boolean = false;
  onSelect: () => void = () => {};
  onLongSelect: () => void = () => {};
  onChanged: () => void = () => {};
  onContinue: (file: WorkspaceFile) => void = () => {};
  allowContinue: boolean = true;
  actions: MenuElement[] = [];
  @State private editing: boolean = false;
  @State private showingPreview: boolean = false;
  @State private newName: string = '';
  @State private tagText: string = '';
  @State private collectionId: string = '';
  @State private collectionName: string = '';
  @State private collections: LumiCollection[] = [];
  @State private sourceNames: string = '';
  @State private thumbnail: string = '';
  @State private count: number = 0;
  @State private originalSize: number = 0;
  @State private feedback: string = '';
  @State private busy: boolean = false;
  private disposed: boolean = false;
  private tempPath: string = '';
  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void { this.count = this.file.pageCount || 0; this.loadInfo(); }
  aboutToDisappear(): void { this.disposed = true; this.cleanup(); }
  private cleanup(): void { try { if (this.tempPath && fs.accessSync(this.tempPath)) { fs.unlinkSync(this.tempPath); } } catch (_) {} }
  private async loadInfo(): Promise<void> {
    try {
      this.collections = await WorkbenchStore.collections();
      const all = await FileService.list(this.ctx(), true);
      if (this.file.mime.startsWith('image/') && this.file.sourcePaths?.length === 1) { this.originalSize = all.find((entry: WorkspaceFile) => entry.path === this.file.sourcePaths?.[0])?.size || 0; }
      this.sourceNames = (this.file.sourcePaths || []).map((path: string) => all.find((entry: WorkspaceFile) => entry.path === path)?.name || '原件已移除').join('、');
      if (this.file.mime === 'application/pdf' && canIUse('SystemCapability.OfficeService.PDFService.Core')) {
        this.tempPath = this.ctx().cacheDir + '/result_' + WorkbenchStore.newId() + '.jpg';
        const info = await taskpool.execute(inspectResult, this.file.path, this.tempPath) as LumiResultInfo;
        if (!this.disposed) { this.thumbnail = info.thumbnail; this.count = info.pages; } else { this.cleanup(); }
      }
    } catch (_) { /* Encrypted/unavailable previews retain a readable file card. */ }
  }
  private startEdit(): void {
    this.newName = this.file.name; this.tagText = (this.file.tags || []).join('，');
    this.collectionId = this.file.collectionId || ''; this.collectionName = ''; this.editing = true;
  }
  private async saveDetails(): Promise<void> {
    if (!this.newName.trim()) { this.feedback = '请输入文件名'; return; }
    this.busy = true;
    try {
      if (this.collectionName.trim()) {
        const collection = new LumiCollection(); collection.id = WorkbenchStore.newId(); collection.name = this.collectionName.trim(); collection.createdAt = Date.now();
        await WorkbenchStore.putCollection(collection); this.collectionId = collection.id;
      }
      const updated = JSON.parse(JSON.stringify(this.file)) as WorkspaceFile;
      updated.name = this.newName.trim(); updated.tags = this.tagText.split(/[,，]/); updated.collectionId = this.collectionId;
      await FileService.updateDetails(this.ctx(), updated); this.editing = false; this.feedback = '已保存'; this.onChanged();
    } catch (error) { this.feedback = (error as Error).message; }
    finally { this.busy = false; }
  }
  private async action(kind: string): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      if (kind === 'export') { await FileService.exportFile(this.ctx(), this.file.path, this.file.name); }
      else if (kind === 'share') { await FileService.share(this.ctx(), this.file.path, this.file.name); }
      else if (kind === 'delete') {
        const choice = await this.getUIContext().getPromptAction().showDialog({ title: '永久删除文件？', message: '删除后无法恢复：' + this.file.name, buttons: [{ text: '取消', color: '#64748B' }, { text: '永久删除', color: '#C44D62' }] });
        if (choice.index !== 1) { return; }
        await FileService.deletePermanently(this.ctx(), this.file); this.onChanged();
      } else { await FileService.setTrash(this.ctx(), this.file, kind === 'trash'); this.onChanged(); }
    } catch (error) { this.feedback = (error as Error).message; }
    finally { this.busy = false; }
  }
  private collectionLabel(): string { return this.collections.find((entry: LumiCollection) => entry.id === (this.editing ? this.collectionId : this.file.collectionId))?.name || '未归组'; }
  private collectionOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '未归组' }];
    return options.concat(this.collections.map((entry: LumiCollection): SelectOption => ({ value: entry.name })));
  }
  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        if (this.selecting) { Text(this.selectionChecked ? '已选' : '选择').fontSize(12).fontColor($r('app.color.brand')).width(36) }
        if (this.thumbnail || this.file.mime.startsWith('image/')) {
          Image(fileUri.getUriFromPath(this.thumbnail || this.file.path)).width(56).height(68).objectFit(ImageFit.Contain).borderRadius(8)
        } else { Text(this.file.mime === 'application/pdf' ? 'PDF' : '文件').fontSize(12).fontColor($r('app.color.brand')).width(52).height(56).textAlign(TextAlign.Center).backgroundColor($r('app.color.brand_soft')).borderRadius(12) }
        Column({ space: 5 }) {
          Text(this.file.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(2)
          Text(FileService.sizeLabel(this.file.size) + (this.count ? ' · ' + this.count.toString() + ' 页' : '') + (this.file.role === 'final' ? ' · 最终成果' : this.file.role === 'intermediate' ? ' · 中间结果' : '')).fontSize(12).fontColor($r('app.color.text_secondary'))
          if (this.file.collectionId || this.file.tags?.length) { Text(this.collectionLabel() + '  ' + (this.file.tags || []).map((tag: string) => '#' + tag).join(' ')).fontSize(11).fontColor($r('app.color.brand')).maxLines(2) }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      if (this.originalSize > this.file.size) { Text('原图 ' + FileService.sizeLabel(this.originalSize) + ' → ' + FileService.sizeLabel(this.file.size) + ' · 减少 ' + Math.round((1 - this.file.size / this.originalSize) * 100).toString() + '%').fontSize(12).fontColor($r('app.color.success')).width('100%') }
      if (this.sourceNames) { Text('来源：' + this.sourceNames).fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(3).width('100%') }
      if (this.selecting) {
        Text(this.selectionChecked ? '点击取消选择' : '点击选择文件').fontSize(12).fontColor($r('app.color.text_secondary'))
      } else if (this.file.trashedAt) {
        Text('回收站保留到你主动永久删除，仍占用本地空间。').fontSize(12).fontColor($r('app.color.text_secondary'))
        Row({ space: 8 }) { Button('恢复').onClick(() => this.action('restore')); Button('永久删除').fontColor($r('app.color.error')).onClick(() => this.action('delete')) }.enabled(!this.busy)
      } else {
        Row({ space: 8 }) {
          Button('预览').fontSize(12).height(36).onClick(() => { this.showingPreview = !this.showingPreview; }).enabled(this.file.mime === 'application/pdf' || this.file.mime.startsWith('image/'))
          Button('导出').fontSize(12).height(36).onClick(() => this.action('export'))
          Button('分享').fontSize(12).height(36).onClick(() => this.action('share'))
          Button('整理').fontSize(12).height(36).onClick(() => this.startEdit())
        }.width('100%').enabled(!this.busy)
        Row({ space: 12 }) {
          if (this.allowContinue && !this.file.name.endsWith('.lumibak')) {
            if (this.actions.length) { Button('继续处理', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).bindMenu(this.actions) }
            else { Button('继续处理', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).onClick(() => this.onContinue(this.file)) }
          }
          Button('移入回收站', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).fontColor($r('app.color.text_secondary')).onClick(() => this.action('trash'))
        }.width('100%').enabled(!this.busy)
      }
      if (this.editing && !this.selecting) {
        TextInput({ text: this.newName, placeholder: '文件名' }).id('result-rename').maxLength(110).onChange((text: string) => { this.newName = text; })
        TextInput({ text: this.tagText, placeholder: '标签，以逗号分隔' }).id('result-tags').maxLength(240).onChange((text: string) => { this.tagText = text; })
        Select(this.collectionOptions()).value(this.collectionLabel()).onSelect((index: number) => { this.collectionId = index > 0 ? this.collections[index - 1].id : ''; })
        TextInput({ text: this.collectionName, placeholder: '或新建集合' }).id('result-collection').maxLength(80).onChange((text: string) => { this.collectionName = text; })
        Row({ space: 8 }) { Button('保存整理').onClick(() => this.saveDetails()); Button('取消').onClick(() => { this.editing = false; }) }.enabled(!this.busy)
      }
      if (this.feedback) { Text(this.feedback).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%') }
      if (this.showingPreview && !this.selecting) { FilePreview({ filePath: this.file.path }) }
    }.padding(16).width('100%').backgroundColor(this.selecting && this.selectionChecked ? $r('app.color.brand_soft') : $r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
      .onClick(() => { if (this.selectable && this.selecting) { this.onSelect(); } })
      .gesture(LongPressGesture({ repeat: false }).onAction(() => { if (this.selectable && !this.selecting) { this.onLongSelect(); } }))
  }
}
