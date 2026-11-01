import { WorkbenchStore } from '../features/workbench/WorkbenchStore';
import { LumiFileSession, LumiFlowSession, LumiFlowRecipe } from '../features/workbench/WorkbenchModels';
import { LumiFlowRoute } from '../features/workbench/FlowPage';
import { LumiResultCard } from '../features/workbench/ResultCard';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { CommonModifier, curves, uiMaterial } from '@kit.ArkUI';
import { LumiIcon } from '../components/LumiIcon';
import { LumiNavigation } from '../components/LumiNavigation';
import { LumiAppearancePicker } from '../components/LumiAppearancePicker';
import { LumiLaunchScreen } from '../components/LumiLaunchScreen';
import { CATEGORIES, TOOLS, ToolCategory, ToolDescriptor, ToolRegistry } from '../core/ToolRegistry';
import { StorageService, HistoryRecord } from '../core/StorageService';
import { FileService, WorkspaceFile } from '../core/FileService';
import { PortableBackup } from '../core/PortableBackup';
import { InventoryReminders } from '../features/inventory/InventoryReminders';
import { InventoryItem } from '../features/inventory/InventoryModels';
import { LocalForm } from '../features/forms/FormModels';
import { LumiRecordRouteParam } from '../core/IncomingRequest';
import { TaskManager, TaskRecord } from '../core/TaskManager';
import { FileToolRouteParam } from '../features/files/FileToolsPage';
import { AnalyticsRouteParam } from '../features/analytics/AnalyticsPage';
import { DeveloperRouteParam } from '../features/developer/DeveloperPage';

@Component
struct LumiFilterChip {
  @Prop selected: boolean = false;
  label: string = '';
  action: () => void = () => {};

  build() {
    Button(this.label, { type: ButtonType.Normal }).height(36).padding({ left: 15, right: 15 }).fontSize(12).borderRadius(13)
      .backgroundColor(this.selected ? $r('app.color.brand') : $r('app.color.surface'))
      .fontColor(this.selected ? $r('app.color.inverse_text') : $r('app.color.text_secondary'))
      .onClick(() => { this.action(); })
  }
}

@Entry
@Component
struct Index {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @StorageProp('lumiIncomingError') @Watch('handleIncomingError') incomingError: string = '';
  @StorageProp('lumiOpenItemId') @Watch('handleReminderOpen') openItemId: string = '';
  @StorageProp('lumiIncomingPaths') @Watch('handleIncoming') incomingPaths: string = '';
  @State fileSessions: LumiFileSession[] = [];
  @State flows: LumiFlowSession[] = [];
  @State recipes: LumiFlowRecipe[] = [];
  @State expandFavorites: boolean = false;
  @State hasFormDraft: boolean = false;
  @State searchItems: InventoryItem[] = [];
  @State searchForms: LocalForm[] = [];
  @State backupStatus: string = '';
  @State lastBackup: string = '';
  @State ready: boolean = false;
  @State startupError: string = '';
  @State startupStep: number = 0;
  @State activeTab: number = 0;
  @State query: string = '';
  @State category: string = 'all';
  @State favoriteOnly: boolean = false;
  @State favorites: string[] = ['json', 'pdf-merge', 'image-convert', 'analytics'];
  @State history: HistoryRecord[] = [];
  @State workspace: WorkspaceFile[] = [];
  @State tasks: TaskRecord[] = [];
  @State historyFilter: string = 'all';
  @State theme: string = 'system';
  @State historyEnabled: boolean = true;
  @State viewportWidth: number = 390;
  @State reduceMotion: boolean = false;
  @State profileBusy: boolean = false;
  @State immersiveSupported: boolean = false;
  @State titleCollapsed: boolean[] = [false, false, false, false];
  private listening: boolean = false;
  private startupRunning: boolean = false;
  private mainScroller: Scroller = new Scroller();
  private tabScrollers: Scroller[] = [new Scroller(), new Scroller(), new Scroller(), new Scroller()];
  private tabsController: TabsController = new TabsController();
  private titleButtonMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: true,
    applyShadow: true,
    lightEffect: { color: $r('app.color.dock_light') }
  });
  private dockMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    interactive: true,
    applyShadow: true,
    lightEffect: { color: $r('app.color.dock_light') }
  });
  private readonly tabSpring: curves.ICurve = curves.springMotion(0.30, 0.82);
  private phoneBarModifier: CommonModifier = new CommonModifier().offset({ y: 24 });
  private defaultBarModifier: CommonModifier = new CommonModifier().offset({ y: 0 });
  private pathStack: NavPathStack = new NavPathStack();
  private readonly motionListener: (enabled: boolean) => void = (enabled: boolean): void => {
    this.reduceMotion = enabled;
    this.pathStack.disableAnimation(enabled);
  };

  aboutToAppear(): void {
    try { this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported(); } catch {}
    this.pathStack.setInterception({
      didShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        operation: NavigationOperation, isAnimated: boolean) => {
        if (to === 'navBar') {
          this.refresh().catch(() => { this.toast('读取最新记录失败'); });
        }
      }
    });
    try {
      this.reduceMotion = accessibility.isAnimationReduceEnabledSync();
    } catch {
      this.reduceMotion = false;
    }
    try {
      accessibility.onAnimationReduceStateChange(this.motionListener);
      this.listening = true;
    } catch {
      this.listening = false;
    }
    this.pathStack.disableAnimation(this.reduceMotion);
    this.initialize();
  }
  aboutToDisappear(): void {
    if (this.listening) { try { accessibility.offAnimationReduceStateChange(this.motionListener); } catch {} }
  }
  onBackPress(): boolean {
    if (this.pathStack.size() > 0) { return false; }
    if (this.activeTab !== 0) { this.selectTab(0); return true; }
    return false;
  }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private toast(message: string): void { this.getUIContext().getPromptAction().showToast({ message: message }); }
  private async initialize(): Promise<void> {
    if (this.startupRunning) { return; }
    this.startupRunning = true;
    this.startupError = '';
    this.startupStep = 0;
    try {
      await StorageService.init(this.context());
      this.startupStep = 1;
      this.theme = await StorageService.getSetting('theme', 'system');
      this.applyTheme(this.theme);
      await TaskManager.recoverInterrupted();
      const stored = JSON.parse(await StorageService.getValue('favorites', JSON.stringify(this.favorites))) as string[];
      if (Array.isArray(stored)) {
        this.favorites = stored.filter((id: string, index: number) => typeof id === 'string' &&
          ToolRegistry.find(id) !== undefined && stored.indexOf(id) === index).slice(0, 26);
      }
      this.historyEnabled = await StorageService.getSetting('historyEnabled', 'true') !== 'false';
      this.startupStep = 2;
      await this.refresh();
      this.lastBackup = await StorageService.getSetting('lastCompleteBackup', '');
      if (this.reduceMotion) { this.ready = true; }
      else { this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => { this.ready = true; }); }
    } catch (error) {
      this.startupError = (error as Error).message === '数据来自更新版本，请升级集萤后打开' ?
        '这些数据来自更新版本，请升级集萤后再打开。' :
        (this.startupStep === 2 ? '文件工作区暂时无法读取，请重试。已有内容会保留。' :
          '本地数据暂时无法读取，请重试。已有内容会保留。');
    } finally { this.startupRunning = false; }
    if (this.ready) { this.handleIncoming(); this.handleReminderOpen(); this.handleIncomingError(); }
  }
  private async refresh(): Promise<void> {
    this.searchItems = JSON.parse(await StorageService.getValue('inventory.items', '[]')) as InventoryItem[];
    this.searchForms = JSON.parse(await StorageService.getValue('forms.schemas', '[]')) as LocalForm[];
    this.fileSessions = await WorkbenchStore.fileSessions();
    this.flows = await WorkbenchStore.flows();
    this.recipes = await WorkbenchStore.recipes();
    this.hasFormDraft = await StorageService.getValue('forms.autodraft', 'null') !== 'null';
    this.history = await StorageService.getHistory();
    this.workspace = await FileService.list(this.context());
    this.tasks = (await TaskManager.list()).filter((task: TaskRecord) => task.state !== 'completed');
  }
  private selectTab(index: number): void {
    if (this.activeTab !== index) {
      // Updating Tabs.index directly skips the native transition.
      this.tabsController.changeIndex(index);
      return;
    }
    this.activateTab(index);
  }
  private activateTab(index: number): void {
    const changed = this.activeTab !== index;
    this.activeTab = index;
    this.tabScrollers[index].scrollEdge(Edge.Top);
    if (changed && index > 1) { this.refresh().catch(() => { this.toast('读取记录失败，请重试'); }); }
  }
  private primaryPageTransition(): TransitionEffect {
    if (this.reduceMotion) { return TransitionEffect.IDENTITY; }
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 220, curve: curves.cubicBezierCurve(0.23, 1, 0.32, 1) }),
      TransitionEffect.IDENTITY
    );
  }
  private openTool(id: string, filePath: string = ''): void {
    if (id === 'inventory' || id === 'forms' || id === 'help') { this.pathStack.pushPathByName(id, undefined); return; }
    if (id === 'analytics') {
      const param = new AnalyticsRouteParam();
      param.filePath = filePath;
      this.pathStack.pushPathByName('analytics', param);
      return;
    }
    const tool = ToolRegistry.find(id);
    if (tool && tool.category === 'developer') {
      const param = new DeveloperRouteParam();
      param.toolId = id;
      this.pathStack.pushPathByName('developer', param);
      return;
    }
    const param = new FileToolRouteParam();
    param.toolId = id;
    param.filePath = filePath;
    this.pathStack.pushPathByName('fileTool', param);
  }
  private openFlow(kind: string, flowId: string = '', recipeId: string = ''): void {
    const param = new LumiFlowRoute(); param.kind = kind; param.flowId = flowId; param.recipeId = recipeId;
    this.pathStack.pushPathByName('workflow', param);
  }
  private resumeTool(session: LumiFileSession): void {
    const param = new FileToolRouteParam(); param.toolId = session.toolId; param.resume = true;
    this.pathStack.pushPathByName('fileTool', param);
  }
  private openCamera(): void {
    const param = new FileToolRouteParam(); param.toolId = 'image-ocr'; param.capture = true;
    this.pathStack.pushPathByName('fileTool', param);
  }
  private async discardFlow(id: string): Promise<void> {
    const choice = await this.getUIContext().getPromptAction().showDialog({ title: '移除流程记录？', message: '已经生成的文件和资料集合仍保留。', buttons: [{ text: '取消', color: '#64748B' }, { text: '移除记录', color: '#2864DA' }] });
    if (choice.index === 1) { try { await WorkbenchStore.deleteFlow(id); await this.refresh(); } catch (error) { this.toast((error as Error).message); } }
  }
  private openCategory(id: string): void {
    if (['inventory', 'forms', 'analytics'].includes(id)) { this.openTool(id); return; }
    this.category = id; this.query = ''; this.favoriteOnly = false; this.selectTab(1);
  }
  private quickTools(): ToolDescriptor[] {
    const result: ToolDescriptor[] = [];
    for (const id of this.favorites) { const tool = ToolRegistry.find(id); if (tool) { result.push(tool); } }
    return result;
  }
  private visibleTools(): ToolDescriptor[] {
    return this.favoriteOnly ? this.quickTools().filter((tool: ToolDescriptor) =>
      `${tool.name} ${tool.description}`.toLowerCase().includes(this.query.trim().toLowerCase())) : ToolRegistry.search(this.query, this.category);
  }
  private async toggleFavorite(id: string): Promise<void> {
    const next = this.favorites.includes(id) ? this.favorites.filter((value: string) => value !== id) : this.favorites.concat(id);

    try { await StorageService.setValue('favorites', JSON.stringify(next)); this.favorites = next; }
    catch { this.toast('收藏保存失败'); }
  }
  private async moveFavorite(id: string): Promise<void> {
    const list = this.favorites.slice(); const index = list.indexOf(id);
    if (index < 1) { return; }
    list.splice(index, 1); list.splice(index - 1, 0, id);
    try { await StorageService.setValue('favorites', JSON.stringify(list)); this.favorites = list; }
    catch { this.toast('排序保存失败'); }
  }
  private visibleHistory(): HistoryRecord[] {
    return this.history.filter((record: HistoryRecord) => (this.historyFilter === 'all' ||
      (this.historyFilter === 'files' ? record.outputPath.length > 0 : record.outputPath.length === 0)) &&
      `${record.title} ${record.detail}`.toLowerCase().includes(this.query.trim().toLowerCase()));
  }
  private dateLabel(time: number): string {
    const date = new Date(time);
    return `${date.getMonth() + 1}月${date.getDate()}日 ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }
  private wide(): boolean { return this.viewportWidth >= 840; }
  private pagePadding(): number { return this.viewportWidth >= 1200 ? 32 : 24; }
  private toolColumns(): number { return this.viewportWidth >= 1360 ? 3 : this.wide() ? 2 : 1; }
  private toolsInColumn(columnIndex: number, totalColumns: number): ToolDescriptor[] {
    return this.visibleTools().filter((_tool: ToolDescriptor, idx: number): boolean => idx % totalColumns === columnIndex);
  }
  private historyInColumn(columnIndex: number, totalColumns: number): HistoryRecord[] {
    return this.visibleHistory().filter((_record: HistoryRecord, idx: number): boolean => idx % totalColumns === columnIndex);
  }
  private primaryTitleIndex(index: number): number { return this.wide() ? this.activeTab : index; }
  private updateTitleCollapse(index: number): void {
    const scroller = this.tabScrollers[index];
    let collapsed = scroller.currentOffset().yOffset > 100;
    try {
      const utils = this.getUIContext().getComponentUtils();
      const heading = utils.getRectangleById(`primary-heading-${index}`);
      const title = utils.getRectangleById(`primary-title-${this.primaryTitleIndex(index)}`);
      if (heading.size.height > 0 && title.size.height > 0) {
        collapsed = heading.windowOffset.y + heading.size.height <= title.windowOffset.y + title.size.height;
      }
    } catch {}
    if (this.titleCollapsed[index] !== collapsed) {
      const states = this.titleCollapsed.slice(); states[index] = collapsed; this.titleCollapsed = states;
    }
  }
  private workspaceSize(): string { return FileService.sizeLabel(this.workspace.reduce((sum: number, file: WorkspaceFile) => sum + file.size, 0)); }
  private applyTheme(value: string): void {
    this.context().getApplicationContext().setColorMode(value === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK :
      value === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }
  private async setTheme(value: string): Promise<void> {
    try { await StorageService.setSetting('theme', value); this.theme = value; this.applyTheme(value); }
    catch { this.toast('外观设置保存失败'); }
  }
  private async toggleHistory(enabled: boolean): Promise<void> {
    try { await StorageService.setSetting('historyEnabled', enabled.toString()); this.historyEnabled = enabled; }
    catch { this.toast('设置保存失败'); }
  }
  private async clearHistory(): Promise<void> {
    const choice = await this.getUIContext().getPromptAction().showDialog({ title: '清空处理记录？',
      message: '只移除操作记录，物品、表单和工作区文件会继续保留。',
      buttons: [{ text: '取消', color: '#6C7E94' }, { text: '清空记录', color: '#C44D62' }] });
    if (choice.index !== 1) { return; }
    try { await StorageService.clearHistory(); await this.refresh(); this.toast('处理记录已清空'); }
    catch { this.toast('清空失败，请重试'); }
  }
  private async backup(): Promise<void> {
    this.profileBusy = true;
    try {
      const file = await PortableBackup.create(this.context(), (message: string) => { this.backupStatus = message; });
      this.lastBackup = new Date().toLocaleString() + ' · ' + FileService.sizeLabel(file.size);
      await StorageService.setSetting('lastCompleteBackup', this.lastBackup);
      this.backupStatus = '完整备份已保存在工作区，可再次导出。';
      await FileService.exportFile(this.context(), file.path, file.name);
      this.toast('完整备份已导出');
    } catch (error) { this.toast((error as Error).message || '备份导出失败'); }
    finally { this.profileBusy = false; }
  }
  private async restore(): Promise<void> {
    this.profileBusy = true;
    try {
      const uris = await new picker.DocumentViewPicker(this.context()).select({ fileSuffixFilters: ['集萤备份|.lumibak,.json'], maxSelectNumber: 1 });
      if (!uris.length) { return; }
      const files = await FileService.importUris(this.context(), uris, 1024 * 1024 * 1024 + 8 * 1024 * 1024 + 13);
      const file = files[0];
      let detail = '旧版资料备份不包含附件。';
      if (file.name.toLowerCase().endsWith('.lumibak')) {
        const manifest = await PortableBackup.inspect(this.context(), file.path);
        detail = new Date(manifest.createdAt).toLocaleString() + ' · ' + manifest.files.length.toString() + ' 个文件，将重新关联附件。';
      }
      const choice = await this.getUIContext().getPromptAction().showDialog({ title: '恢复数据备份',
        message: detail + '\n备份中的业务模块将替换本机对应模块；现有工作区文件保留。恢复前会自动保存当前资料快照。',
        buttons: [{ text: '取消', color: '#6C7E94' }, { text: '恢复', color: '#3068DB' }] });
      if (choice.index !== 1) { return; }
      await FileService.writeText(this.context(), '集萤_恢复前快照_' + Date.now().toString() + '.json', await StorageService.exportBackup());
      if (file.name.toLowerCase().endsWith('.lumibak')) { await PortableBackup.restore(this.context(), file.path, (message: string) => { this.backupStatus = message; }); }
      else { await StorageService.restoreBackup(await FileService.readText(this.context(), file.path)); }
      this.favorites = JSON.parse(await StorageService.getValue('favorites', JSON.stringify(this.favorites))) as string[];
      await this.refresh();
      try { await InventoryReminders.sync(this.searchItems, this.context()); } catch (_) { this.toast('资料已恢复，请到物品详情更新系统提醒'); }
      this.backupStatus = '恢复完成'; this.toast('资料已恢复');
    } catch (error) { this.toast((error as Error).message || '备份恢复失败'); }
    finally { this.profileBusy = false; }
  }
  private handleIncomingError(): void {
    if (!this.ready || !this.incomingError) { return; }
    this.toast(this.incomingError); AppStorage.setOrCreate('lumiIncomingError', '');
  }
  private handleReminderOpen(): void {
    if (!this.ready || !this.openItemId) { return; }
    const id = this.openItemId; AppStorage.setOrCreate('lumiOpenItemId', ''); this.openRecord('inventory', id);
  }
  private handleIncoming(): void {
    if (!this.ready || !this.incomingPaths) { return; }
    const paths = JSON.parse(this.incomingPaths) as string[];
    AppStorage.setOrCreate('lumiIncomingPaths', '');
    if (!paths.length) { return; }
    this.refresh().then(() => {
      const files = this.workspace.filter((file: WorkspaceFile) => paths.includes(file.path));
      if (!files.length) { return; }
      if (files.length === 1 && files[0].name.toLowerCase().endsWith('.xlsx')) { this.openTool('analytics', files[0].path); return; }
      const param = new FileToolRouteParam();
      param.filePaths = files.map((file: WorkspaceFile) => file.path);
      param.toolId = files.every((file: WorkspaceFile) => file.mime === 'application/pdf') ? (files.length > 1 ? 'pdf-merge' : 'pdf-edit') :
        files.every((file: WorkspaceFile) => file.mime.startsWith('image/')) ? (files.length > 1 ? 'images-pdf' : 'image-convert') : 'file-workspace';
      this.pathStack.pushPathByName('fileTool', param);
    }).catch(() => { this.toast('分享文件导入失败，请重新分享'); });
  }
  private matchingItems(): InventoryItem[] {
    const term = this.query.trim().toLowerCase();
    return term ? this.searchItems.filter((item: InventoryItem) => [item.name, item.brand, item.model, item.category, item.notes].join(' ').toLowerCase().includes(term)).slice(0, 20) : [];
  }
  private matchingForms(): LocalForm[] {
    const term = this.query.trim().toLowerCase();
    return term ? this.searchForms.filter((form: LocalForm) => [form.title, form.description].join(' ').toLowerCase().includes(term)).slice(0, 20) : [];
  }
  private matchingFiles(): WorkspaceFile[] {
    const term = this.query.trim().toLowerCase();
    return term ? this.workspace.filter((file: WorkspaceFile) => file.name.toLowerCase().includes(term)).slice(0, 20) : [];
  }
  private openRecord(kind: string, id: string): void {
    const param = new LumiRecordRouteParam(); param.recordId = id;
    this.pathStack.pushPathByName(kind, param);
  }
  private async cleanCache(): Promise<void> {
    try {
      const directory = this.context().cacheDir;
      for (const name of await fs.listFile(directory)) {
        const path = directory + '/' + name;
        if ((await fs.stat(path)).isDirectory()) { await fs.rmdir(path); } else { await fs.unlink(path); }
      }
      this.toast('临时缓存已清理');
    } catch { this.toast('部分临时文件正在使用，请稍后重试'); }
  }
  private information(title: string, message: string): void {
    this.getUIContext().getPromptAction().showDialog({ title: title, message: message, buttons: [{ text: '知道了', color: '#3068DB' }] });
  }

  @Builder
  pageHeading(title: string, subtitle: string, index: number) {
    Column({ space: 8 }) {
      Text(title).fontSize(this.wide() ? 34 : 28).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).lineHeight(this.wide() ? 44 : 38)
      Text(subtitle).fontSize(13).lineHeight(21).fontColor($r('app.color.text_secondary'))
    }.id(`primary-heading-${index}`).width('100%').alignItems(HorizontalAlign.Start).margin({ top: 14, bottom: 6 })
  }
  @Builder
  searchBox(placeholder: string) {
    Row({ space: 10 }) {
      LumiIcon({ name: 'search', iconSize: 20, muted: true })
      TextInput({ text: this.query, placeholder: placeholder }).id('tool-search').layoutWeight(1).height(48).padding({ left: 0, right: 0 })
        .backgroundColor(Color.Transparent).fontSize(14).fontColor($r('app.color.text_primary')).placeholderColor($r('app.color.text_secondary'))
        .onChange((value: string) => { this.query = value; })
    }.padding({ left: 16, right: 12 }).width('100%').borderRadius(18).backgroundColor($r('app.color.surface'))
  }
  @Builder
  sectionTitle(title: string, action: string, onAction: () => void) {
    Row() {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      Blank()
      Button(action, { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).height(36).fontColor($r('app.color.text_secondary')).onClick(onAction)
    }.width('100%')
  }
  @Builder
  heroCard() {
    Column({ space: 18 }) {
      Row() {
        Row({ space: 6 }) {
          LumiIcon({ name: 'shield', iconSize: 14 })
          Text('本地优先 · 即开即用').fontSize(11).fontColor($r('app.color.brand_ink'))
        }
        Blank()
        Text('LUMIKIT / 01').fontSize(10).letterSpacing(1.2).fontColor($r('app.color.brand_ink'))
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 9 }) {
          Text('让繁杂，\n变简单。').fontSize(this.wide() ? 38 : 31).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).lineHeight(this.wide() ? 48 : 42)
          Text('文件、灵感和生活，\n都在这里井然有序。').fontSize(12).lineHeight(21).fontColor($r('app.color.brand_ink'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.lumi_logo')).width(this.wide() ? 138 : 112).height(this.wide() ? 138 : 112).rotate({ angle: 12 })
      }.width('100%')
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          Image($r('app.media.ic_import_inverse')).width(18).height(18)
          Text('导入文件，开始处理').fontSize(14).fontWeight(FontWeight.Medium)
          Blank()
          Text('→').fontSize(20)
        }.padding({ left: 18, right: 18 }).width('100%')
      }.width('100%').height(50).borderRadius(17).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text'))
        .onClick(() => { this.openTool('file-workspace'); })
    }.padding(24).width('100%').borderRadius(28).backgroundColor($r('app.color.hero')).alignItems(HorizontalAlign.Start)
  }
  @Builder
  quickSection() {
    Column({ space: 8 }) {
      this.sectionTitle('我的常用', '自定义', () => { this.favoriteOnly = true; this.query = ''; this.selectTab(1); })
      Grid() {
        ForEach(this.expandFavorites ? this.quickTools() : this.quickTools().slice(0, 4), (tool: ToolDescriptor) => {
          GridItem() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 8 }) {
                LumiIcon({ name: tool.icon, iconSize: 23 })
                Text(tool.name.replace('JSON 格式化', 'JSON')).fontSize(11).maxLines(1).fontColor($r('app.color.text_primary'))
              }.width('100%').height(86).justifyContent(FlexAlign.Center)
            }.width('100%').padding(0).backgroundColor($r('app.color.surface')).borderRadius(20).onClick(() => this.openTool(tool.id))
          }
        }, (tool: ToolDescriptor) => tool.id)
      }.columnsTemplate('1fr 1fr 1fr 1fr').columnsGap(8).rowsGap(8).height(Math.max(1, Math.ceil((this.expandFavorites ? this.favorites.length : Math.min(this.favorites.length, 4)) / 4)) * 94).enableScrollInteraction(false)
      if (this.favorites.length > 4) { Button(this.expandFavorites ? '收起常用工具' : '展开全部 ' + this.favorites.length.toString() + ' 个工具', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).onClick(() => { this.expandFavorites = !this.expandFavorites; }) }
      ForEach(this.recipes, (recipe: LumiFlowRecipe) => {
        Row({ space: 8 }) {
          Button('流程 · ' + recipe.name, { buttonStyle: ButtonStyleMode.TEXTUAL }).layoutWeight(1).onClick(() => this.openFlow(recipe.kind, '', recipe.id))
          Button('移除', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).onClick(() => { WorkbenchStore.deleteRecipe(recipe.id).then(() => this.refresh()).catch((error: Error) => this.toast(error.message)); })
        }.width('100%')
      }, (recipe: LumiFlowRecipe) => recipe.id)
    }.width('100%')
  }
  @Builder
  categoryCard(item: ToolCategory) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 12 }) {
        Row() {
          LumiIcon({ name: item.icon, iconSize: 25 })
          Blank()
          Text('↗').fontSize(20).fontColor($r('app.color.text_secondary'))
        }.width('100%')
        Column({ space: 6 }) {
          Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(item.caption).fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(1)
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.padding(this.viewportWidth < 360 ? 16 : 20).width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').padding(0).backgroundColor($r('app.color.surface')).borderRadius(24).accessibilityText(item.name)
      .onClick(() => { this.openCategory(item.id); })
  }
  @Builder
  categoriesSection() {
    Column({ space: 8 }) {
      this.sectionTitle('为每件小事，找到工具', '全部 →', () => { this.category = 'all'; this.favoriteOnly = false; this.query = ''; this.selectTab(1); })
      Grid() {
        ForEach(CATEGORIES, (item: ToolCategory) => { GridItem() { this.categoryCard(item) } }, (item: ToolCategory) => item.id)
      }.columnsTemplate(this.wide() ? '1fr 1fr 1fr' : '1fr 1fr').columnsGap(12).rowsGap(12).height(this.wide() ? 270 : 405).width('100%')
        .enableScrollInteraction(false)
    }.width('100%')
  }
  @Builder
  emptyState(icon: string, title: string, description: string) {
    Column({ space: 12 }) {
      Column() { LumiIcon({ name: icon, iconSize: 28, muted: true }) }.width(62).height(62).justifyContent(FlexAlign.Center).borderRadius(21).backgroundColor($r('app.color.soft_surface'))
      Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
      Text(description).fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(20).textAlign(TextAlign.Center)
    }.padding(28).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }
  @Builder
  historyRow(record: HistoryRecord) {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column() { LumiIcon({ name: ToolRegistry.find(record.toolId)?.icon || 'history', iconSize: 21 }) }.width(44).height(44)
          .justifyContent(FlexAlign.Center).borderRadius(14).backgroundColor($r('app.color.brand_soft'))
        Column({ space: 5 }) {
          Text(record.title).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1).fontColor($r('app.color.text_primary'))
          Text(`${record.detail} · ${this.dateLabel(record.createdAt)}`).fontSize(11).maxLines(2).fontColor($r('app.color.text_secondary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('打开', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(40).fontSize(12).fontColor($r('app.color.brand'))
          .onClick(() => { this.openTool(ToolRegistry.find(record.toolId) ? record.toolId : 'file-workspace', record.outputPath); })
      }.width('100%')
      if (record.outputPath.length > 0) {
        Row({ space: 8 }) {
          Button('保存到文件').height(34).fontSize(12).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.brand')).onClick(() => {
            FileService.exportFile(this.context(), record.outputPath, record.outputPath.split('/').pop() || 'LumiKit结果')
              .then(() => { this.toast('已保存'); }).catch(() => { this.toast('未导出；文件可能已移除或操作已取消'); });
          })
          Button('分享').height(34).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.brand')).onClick(() => {
            FileService.share(this.context(), record.outputPath, record.title).catch(() => { this.toast('分享未完成'); });
          })
        }.width('100%')
      }
    }.padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
  }
  @Builder
  recentSection() {
    Column({ space: 8 }) {
      this.sectionTitle('最近成果', '全部文件 →', () => { this.openTool('file-workspace'); })
      if (this.workspace.filter((file: WorkspaceFile) => file.role === 'final').length === 0) {
        this.emptyState('folder', '让第一件小事，在这里完成', '从提交材料或整理截图开始，成果会自动保存在本机。')
      }
      ForEach(this.workspace.filter((file: WorkspaceFile) => file.role === 'final').slice(0, 3), (file: WorkspaceFile) => {
        LumiResultCard({ file: file, onChanged: () => { this.refresh(); }, onContinue: (entry: WorkspaceFile) => { this.openTool('file-workspace', entry.path); } })
      }, (file: WorkspaceFile) => JSON.stringify(file))
    }.width('100%')
  }
  @Builder
  startSection() {
    Column({ space: 14 }) {
      Text('从一件小事开始').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Row({ space: 8 }) {
        Button('导入文件').layoutWeight(1).height(44).fontSize(13).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openTool('file-workspace'))
        Button('拍照识字').layoutWeight(1).height(44).fontSize(13).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openCamera())
        Button('处理文本').layoutWeight(1).height(44).fontSize(13).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openTool('text-convert'))
      }.width('100%')
      Button({ type: ButtonType.Normal }) {
        Column({ space: 6 }) {
          Text('提交材料 →').fontSize(21).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand_ink'))
          Text('选好文件，整理页面，检查大小，再分享').fontSize(13).fontColor($r('app.color.brand_ink'))
        }.width('100%').alignItems(HorizontalAlign.Start).padding(22)
      }.id('home-materials').padding(0).width('100%').borderRadius(24).backgroundColor($r('app.color.hero')).onClick(() => this.openFlow('materials'))
      Row({ space: 8 }) {
        Button('截图整理成 PDF').id('home-screenshots').layoutWeight(1).height(46).fontSize(13).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openFlow('screenshots'))
        Button('登记一件物品').layoutWeight(1).height(46).fontSize(13).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => { const param = new LumiRecordRouteParam(); param.createNew = true; this.pathStack.pushPathByName('inventory', param); })
      }.width('100%')
    }.width('100%')
  }
  @Builder
  resumeSection() {
    if (this.fileSessions.length || this.flows.some((flow: LumiFlowSession) => flow.stage < 3) || this.hasFormDraft) {
      Column({ space: 10 }) {
        this.sectionTitle('继续上次', '查看记录 →', () => this.selectTab(2))
        ForEach(this.flows.filter((flow: LumiFlowSession) => flow.stage < 3).slice(0, 3), (flow: LumiFlowSession) => {
          Row({ space: 8 }) {
            Column({ space: 5 }) {
              Text(flow.name).fontSize(15).fontColor($r('app.color.text_primary'))
              Text(['选择材料', '整理页面', '设置大小'][flow.stage] + ' · ' + flow.inputs.length.toString() + ' 个原件').fontSize(12).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button('继续').id('resume-flow-' + flow.id).onClick(() => this.openFlow(flow.kind, flow.id))
          }.padding(16).backgroundColor($r('app.color.surface')).borderRadius(20).width('100%')
        }, (flow: LumiFlowSession) => flow.id)
        ForEach(this.fileSessions.slice(0, 3), (session: LumiFileSession) => {
          Button('继续 ' + (ToolRegistry.find(session.toolId)?.name || '文件处理') + ' · ' + session.paths.length.toString() + ' 个文件', { buttonStyle: ButtonStyleMode.TEXTUAL }).width('100%').onClick(() => this.resumeTool(session))
        }, (session: LumiFileSession) => session.toolId)
        if (this.hasFormDraft) { Button('继续填写表单', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => this.openTool('forms')) }
      }.width('100%')
    }
  }
  @Builder
  localNotice() {
    Row({ space: 7 }) {
      LumiIcon({ name: 'shield', iconSize: 14, muted: true })
      Text('无需账号 · 本地处理 · 无广告').fontSize(11).fontColor($r('app.color.text_secondary'))
    }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 8, bottom: 8 })
  }
  @Builder
  homePage() {
    Column({ space: 18 }) {
      this.pageHeading('今天，有什么需要处理？', '把琐碎交给集萤，把时间留给喜欢的事。', 0)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          LumiIcon({ name: 'search', iconSize: 20, muted: true })
          Text('搜索工具、文件和资料').fontSize(14).fontColor($r('app.color.text_secondary'))
        }.width('100%').padding(16)
      }.width('100%').height(50).padding(0).backgroundColor($r('app.color.surface')).borderRadius(18)
        .onClick(() => { this.query = ''; this.category = 'all'; this.favoriteOnly = false; this.selectTab(1); })
      if (this.wide()) {
        Row({ space: 22 }) {
          Column({ space: 18 }) { this.startSection(); this.resumeSection(); this.quickSection() }.layoutWeight(1)
          Column({ space: 18 }) { this.recentSection(); this.categoriesSection() }.layoutWeight(1.25)
        }.alignItems(VerticalAlign.Top).width('100%')
        this.localNotice()
      } else {
        this.startSection()
        this.resumeSection()
        this.quickSection()
        this.recentSection()
        this.categoriesSection()
        this.localNotice()
      }
    }.width('100%')
  }
  @Builder
  toolRow(tool: ToolDescriptor) {
    Stack({ alignContent: Alignment.End }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 13 }) {
          Column() { LumiIcon({ name: tool.icon, iconSize: 23 }) }.width(46).height(46).justifyContent(FlexAlign.Center).borderRadius(15).backgroundColor($r('app.color.brand_soft'))
          Column({ space: 6 }) {
            Text(tool.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(tool.description).fontSize(11).lineHeight(17).maxLines(2).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%').padding({ left: 16, top: 16, bottom: 16, right: (this.favoriteOnly && this.favorites.indexOf(tool.id) > 0) ? 118 : 72 })
      }.id('tool-' + tool.id).width('100%').padding(0).backgroundColor($r('app.color.surface')).borderRadius(22)
        .accessibilityText(tool.name).onClick(() => { this.openTool(tool.id); })
      Row({ space: 4 }) {
        if (this.favoriteOnly && this.favorites.indexOf(tool.id) > 0) {
          Button('↑', { buttonStyle: ButtonStyleMode.TEXTUAL }).id('favorite-up-' + tool.id).width(36).height(44).fontSize(20).fontColor($r('app.color.brand'))
            .accessibilityText(`将${tool.name}上移`).onClick(() => { this.moveFavorite(tool.id); })
        }
        Button({ type: ButtonType.Normal }) {
          Text(this.favorites.includes(tool.id) ? '★' : '☆').fontSize(25)
            .fontColor(this.favorites.includes(tool.id) ? $r('app.color.brand') : $r('app.color.text_secondary'))
        }.id('favorite-' + tool.id).height(44).width(40).backgroundColor(Color.Transparent).borderRadius(15)
          .accessibilityText(`${this.favorites.includes(tool.id) ? '取消收藏' : '收藏'}${tool.name}`).onClick(() => { this.toggleFavorite(tool.id); })
      }.padding({ right: 14 }).hitTestBehavior(HitTestMode.Transparent)
    }.width('100%')
  }
  @Builder
  categoryMenu() {
    Menu() {
      ForEach(CATEGORIES, (item: ToolCategory) => {
        MenuItem({ content: item.name })
          .id('category-' + item.id)
          .selected(!this.favoriteOnly && this.category === item.id)
          .onClick(() => { this.category = item.id; this.favoriteOnly = false; })
      }, (item: ToolCategory) => item.id)
    }
  }
  @Builder
  toolFilters() {
    Row({ space: 8 }) {
      LumiFilterChip({ label: '全部', selected: !this.favoriteOnly && this.category === 'all',
        action: () => { this.category = 'all'; this.favoriteOnly = false; } })
      LumiFilterChip({ label: '★ 常用', selected: this.favoriteOnly, action: () => { this.favoriteOnly = true; } })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 5 }) {
          Text(!this.favoriteOnly && this.category !== 'all' ?
            (CATEGORIES.find((item: ToolCategory) => item.id === this.category)?.name || '分类') : '分类')
            .fontSize(12).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          LumiIcon({ name: 'chevron', iconSize: 12, muted: this.favoriteOnly || this.category === 'all' })
            .rotate({ angle: 90 })
        }.padding({ left: 12, right: 12 })
      }.id('tool-category-menu').layoutWeight(1).height(36).borderRadius(13)
        .backgroundColor(!this.favoriteOnly && this.category !== 'all' ? $r('app.color.brand_soft') : $r('app.color.surface'))
        .fontColor($r('app.color.brand')).accessibilityText('选择工具分类')
        .bindMenu(this.categoryMenu)
    }.width('100%')
  }
  @Builder
  toolsPage() {
    Column({ space: 16 }) {
      this.pageHeading('每一件小事，都有解法。', `${TOOLS.length} 个本地工具，陪你从容处理日常。`, 1)
      this.searchBox('搜索工具、文件、物品和表单')
      if (this.query.trim()) {
        ForEach(this.matchingItems(), (item: InventoryItem) => {
          Button('物品 · ' + item.name).width('100%').height(46).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openRecord('inventory', item.id))
        }, (item: InventoryItem) => item.id)
        ForEach(this.matchingForms(), (form: LocalForm) => {
          Button('表单 · ' + form.title).width('100%').height(46).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openRecord('forms', form.id))
        }, (form: LocalForm) => form.id)
        ForEach(this.matchingFiles(), (file: WorkspaceFile) => {
          Button('文件 · ' + file.name).width('100%').height(46).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(() => this.openTool(file.name.toLowerCase().endsWith('.xlsx') || file.mime === 'text/csv' ? 'analytics' : file.mime === 'application/pdf' ? 'pdf-edit' : file.mime.startsWith('image/') ? 'image-convert' : 'file-workspace', file.path))
        }, (file: WorkspaceFile) => file.id)
      }
      this.toolFilters()
      if (this.favoriteOnly) {
        Row() {
          Text('收藏所有需要的工具；点 ↑ 调整顺序').fontSize(12).fontColor($r('app.color.text_secondary'))
          Blank()
          Button('添加', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(36).fontSize(12).fontColor($r('app.color.brand'))
            .onClick(() => { this.favoriteOnly = false; this.category = 'all'; })
        }.width('100%')
      }
      if (this.visibleTools().length === 0 && this.matchingItems().length === 0 && this.matchingForms().length === 0 && this.matchingFiles().length === 0) { this.emptyState('search', '暂时没有找到', '换个关键词，或从“全部”里看看。') }
      if (this.toolColumns() === 3) {
        Row({ space: 14 }) {
          Column({ space: 14 }) {
            ForEach(this.toolsInColumn(0, 3), (tool: ToolDescriptor) => { this.toolRow(tool) }, (tool: ToolDescriptor) => tool.id)
          }.layoutWeight(1)
          Column({ space: 14 }) {
            ForEach(this.toolsInColumn(1, 3), (tool: ToolDescriptor) => { this.toolRow(tool) }, (tool: ToolDescriptor) => tool.id)
          }.layoutWeight(1)
          Column({ space: 14 }) {
            ForEach(this.toolsInColumn(2, 3), (tool: ToolDescriptor) => { this.toolRow(tool) }, (tool: ToolDescriptor) => tool.id)
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else if (this.toolColumns() === 2) {
        Row({ space: 14 }) {
          Column({ space: 14 }) {
            ForEach(this.toolsInColumn(0, 2), (tool: ToolDescriptor) => { this.toolRow(tool) }, (tool: ToolDescriptor) => tool.id)
          }.layoutWeight(1)
          Column({ space: 14 }) {
            ForEach(this.toolsInColumn(1, 2), (tool: ToolDescriptor) => { this.toolRow(tool) }, (tool: ToolDescriptor) => tool.id)
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        ForEach(this.visibleTools(), (tool: ToolDescriptor) => { this.toolRow(tool) }, (tool: ToolDescriptor) => tool.id)
      }
    }.width('100%')
  }
  @Builder
  historyOverviewCard(icon: string, value: string, label: string, caption: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        Row() {
          Column() { LumiIcon({ name: icon, iconSize: 21 }) }.width(42).height(42).justifyContent(FlexAlign.Center)
            .borderRadius(14).backgroundColor($r('app.color.brand_soft'))
          Blank()
          Text('↗').fontSize(18).fontColor($r('app.color.text_secondary'))
        }.width('100%')
        Text(value).fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Text(caption).fontSize(11).fontColor($r('app.color.text_secondary')).maxLines(1)
      }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).padding(0).backgroundColor($r('app.color.surface')).borderRadius(22).onClick(action)
  }
  @Builder
  historyPage() {
    Column({ space: 16 }) {
      this.pageHeading('做过的事，都有迹可循。', '文件处理与本地项目记录，随时回来继续。', 2)
      if (this.wide()) {
        Row({ space: 14 }) {
          this.historyOverviewCard('history', `${this.history.length} 条`, '本地处理记录',
            this.historyEnabled ? '自动记录最近使用的工具与输出' : '已暂停记录新的处理历史', () => { this.selectTab(1); })
          this.historyOverviewCard('folder', `${this.workspace.length} 个`, '文件工作区',
            `共占用 ${this.workspaceSize()} · 点击管理副本`, () => { this.openTool('file-workspace'); })
          this.historyOverviewCard('inventory', `${this.searchItems.length + this.searchForms.length} 项`, '物品与表单资料',
            `${this.searchItems.length} 件物品 · ${this.searchForms.length} 张本地表单`, () => { this.openTool('inventory'); })
        }.width('100%')
      }
      ForEach(this.flows, (flow: LumiFlowSession) => {
        Row({ space: 8 }) {
          Button(flow.name + (flow.stage === 3 ? ' · 已完成' : ' · 待继续'), { buttonStyle: ButtonStyleMode.TEXTUAL }).layoutWeight(1).onClick(() => this.openFlow(flow.kind, flow.id))
          Button('移除记录', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).onClick(() => this.discardFlow(flow.id))
        }.width('100%')
      }, (flow: LumiFlowSession) => flow.id)
      if (this.tasks.length > 0) {
        Text('待继续的任务').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
        ForEach(this.tasks.slice(0, 5), (task: TaskRecord) => {
          Row({ space: 12 }) {
            Column({ space: 6 }) {
              Text(`${task.title} · ${task.state === 'cancelled' ? '已取消' : task.state === 'failed' ? '未完成' : '处理中'}`)
                .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Text(task.error || `处理进度 ${task.progress}%`).fontSize(11).lineHeight(18).maxLines(2).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(40).fontSize(12).fontColor($r('app.color.brand'))
              .onClick(() => {
                const session = this.fileSessions.find((entry: LumiFileSession) => entry.toolId === task.toolId);
                if (session) { this.resumeTool(session); } else { this.openTool(task.toolId, this.workspace.find((file: WorkspaceFile) => task.inputPaths.includes(file.path))?.path || ''); }
              })
          }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
        }, (task: TaskRecord) => task.id)
      }
      this.searchBox('搜索处理记录')
      Row({ space: 8 }) {
        LumiFilterChip({ label: '全部', selected: this.historyFilter === 'all', action: () => { this.historyFilter = 'all'; } })
        LumiFilterChip({ label: '文件结果', selected: this.historyFilter === 'files', action: () => { this.historyFilter = 'files'; } })
        LumiFilterChip({ label: '其他记录', selected: this.historyFilter === 'other', action: () => { this.historyFilter = 'other'; } })
        Blank()
        Button('工作区', { buttonStyle: ButtonStyleMode.TEXTUAL }).height(36).fontSize(12).fontColor($r('app.color.brand'))
          .onClick(() => { this.openTool('file-workspace'); })
      }.width('100%')
      if (this.visibleHistory().length === 0) { this.emptyState('history', '还没有处理记录', '从一个工具开始，让繁杂变得简单。') }
      else if (this.wide() && this.visibleHistory().length > 1) {
        Row({ space: 14 }) {
          Column({ space: 14 }) {
            ForEach(this.historyInColumn(0, 2), (record: HistoryRecord) => { this.historyRow(record) }, (record: HistoryRecord) => record.id)
          }.layoutWeight(1)
          Column({ space: 14 }) {
            ForEach(this.historyInColumn(1, 2), (record: HistoryRecord) => { this.historyRow(record) }, (record: HistoryRecord) => record.id)
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        ForEach(this.visibleHistory(), (record: HistoryRecord) => { this.historyRow(record) }, (record: HistoryRecord) => record.id)
      }
      if (this.history.length > 0) {
        Button('清空处理记录', { buttonStyle: ButtonStyleMode.TEXTUAL }).fontSize(12).fontColor($r('app.color.text_secondary')).onClick(() => { this.clearHistory(); })
      }
    }.width('100%')
  }
  @Builder
  settingRow(icon: string, title: string, detail: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        LumiIcon({ name: icon, iconSize: 21 })
        Column({ space: 5 }) {
          Text(title).fontSize(14).fontColor($r('app.color.text_primary'))
          if (detail.length > 0) { Text(detail).fontSize(11).lineHeight(18).fontColor($r('app.color.text_secondary')) }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        LumiIcon({ name: 'chevron', iconSize: 16, muted: true })
      }.width('100%').padding(18)
    }.width('100%').padding(0).borderRadius(20).backgroundColor($r('app.color.surface')).onClick(action)
  }
  @Builder
  profileBrandCard() {
    Row({ space: 16 }) {
      Image($r('app.media.lumi_logo')).width(70).height(70).borderRadius(22)
      Column({ space: 7 }) {
        Text('集萤 LumiKit').fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
        Text('让繁杂，变简单。').fontSize(13).fontColor($r('app.color.text_secondary'))
        Text('本地工具工作台 · 1.2.0').fontSize(11).fontColor($r('app.color.brand'))
      }.alignItems(HorizontalAlign.Start)
    }.padding(24).width('100%').backgroundColor($r('app.color.hero')).borderRadius(28)
  }
  @Builder
  profileAppearanceCard() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        LumiIcon({ name: 'sun', iconSize: 21 })
        Text('外观').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.theme === 'dark' ? '深色' : this.theme === 'light' ? '浅色' : '跟随系统').fontSize(12).fontColor($r('app.color.text_secondary'))
      }.width('100%')
      LumiAppearancePicker({ theme: this.theme, onSelect: (theme: string): void => { this.setTheme(theme); } })
    }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }
  @Builder
  profileHistoryToggleCard() {
    Row() {
      Column({ space: 6 }) {
        Text('保存操作记录').fontSize(14).fontColor($r('app.color.text_primary'))
        Text('开发者工具输入正文始终不保存').fontSize(11).fontColor($r('app.color.text_secondary'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: this.historyEnabled }).selectedColor($r('app.color.brand')).onChange((enabled: boolean) => { this.toggleHistory(enabled); })
    }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
  }
  @Builder
  profileBackupSection() {
    Column({ space: 12 }) {
      if (this.lastBackup) { Text('最近备份：' + this.lastBackup).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%') }
      if (this.backupStatus) { Text(this.backupStatus).fontSize(12).fontColor($r('app.color.brand')).width('100%') }
      Text('数据备份').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
      Text('完整备份包含物品、表单、分析项目、记录及工作区文件，可换机恢复附件。').fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary')).width('100%')
      Row({ space: 12 }) {
        Button('导出完整备份').layoutWeight(1).height(46).fontSize(13).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text'))
          .enabled(!this.profileBusy).onClick(() => { this.backup(); })
        Button('恢复备份').layoutWeight(1).height(46).fontSize(13)
          .backgroundColor(this.wide() ? $r('app.color.soft_surface') : $r('app.color.surface')).fontColor($r('app.color.brand'))
          .enabled(!this.profileBusy).onClick(() => { this.restore(); })
      }.width('100%')
    }.width('100%').padding(this.wide() ? 20 : 0)
      .backgroundColor(this.wide() ? $r('app.color.surface') : Color.Transparent)
      .borderRadius(this.wide() ? 24 : 0)
  }
  @Builder
  profilePage() {
    Column({ space: 16 }) {
      this.pageHeading(this.wide() ? '自己的工具，自己的节奏。' : '自己的工具，\n自己的节奏。', '数据在本地，安心也在。', 3)
      if (this.wide()) {
        Row({ space: 20 }) {
          Column({ space: 16 }) {
            this.profileBrandCard()
            this.profileAppearanceCard()
            this.profileHistoryToggleCard()
            this.settingRow('info', '使用说明', '操作步骤、支持格式与常见问题', () => { this.openTool('help'); })
          }.layoutWeight(1)
          Column({ space: 16 }) {
            this.settingRow('folder', '文件工作区', `${this.workspace.length} 个文件 · ${this.workspaceSize()} · 导出时选择保存位置`, () => { this.openTool('file-workspace'); })
            this.profileBackupSection()
            this.settingRow('shield', '隐私与数据', '无需账号，核心处理不联网', () => {
              this.information('隐私与数据', '集萤不要求登录，不含广告或统计 SDK。文件仅通过系统选择器由你主动选择，并复制到应用私有目录。核心工具离线运行；本应用未申请网络与广泛存储权限。开发者工具正文默认不保存，可自愿开启本地草稿。系统分享或保存由你主动发起。卸载应用会删除应用内数据，请提前导出文件与数据备份。');
            })
            this.settingRow('folder', '清理临时缓存', '保留工作区文件、物品、表单与记录', () => { this.cleanCache(); })
            this.settingRow('info', '关于集萤', '六种工具，一处安心的工作台', () => {
              this.information('集萤 LumiKit · 1.2.0', '让繁杂，变简单。\n\nHarmonyOS 原生本地工具工作台。\n26 个本地工具，支持完整备份、PDF 页面整理、图片文字识别、Excel 数据分析与到期提醒。\n\nPDF 图像压缩会生成静态副本，原件保留。文字识别和到期通知取决于设备系统能力。');
            })
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        this.profileBrandCard()
        this.settingRow('info', '使用说明', '操作步骤、支持格式与常见问题', () => { this.openTool('help'); })
        this.profileAppearanceCard()
        this.settingRow('folder', '文件工作区', `${this.workspace.length} 个文件 · ${this.workspaceSize()} · 导出时选择保存位置`, () => { this.openTool('file-workspace'); })
        this.profileHistoryToggleCard()
        this.profileBackupSection()
        this.settingRow('shield', '隐私与数据', '无需账号，核心处理不联网', () => {
          this.information('隐私与数据', '集萤不要求登录，不含广告或统计 SDK。文件仅通过系统选择器由你主动选择，并复制到应用私有目录。核心工具离线运行；本应用未申请网络与广泛存储权限。开发者工具正文默认不保存，可自愿开启本地草稿。系统分享或保存由你主动发起。卸载应用会删除应用内数据，请提前导出文件与数据备份。');
        })
        this.settingRow('folder', '清理临时缓存', '保留工作区文件、物品、表单与记录', () => { this.cleanCache(); })
        this.settingRow('info', '关于集萤', '六种工具，一处安心的工作台', () => {
          this.information('集萤 LumiKit · 1.2.0', '让繁杂，变简单。\n\nHarmonyOS 原生本地工具工作台。\n26 个本地工具，支持完整备份、PDF 页面整理、图片文字识别、Excel 数据分析与到期提醒。\n\nPDF 图像压缩会生成静态副本，原件保留。文字识别和到期通知取决于设备系统能力。');
        })
      }
      this.localNotice()
    }.width('100%')
  }
  @Builder
  tabPage(index: number) {
    Scroll(this.tabScrollers[index]) {
      Column() {
        if (index === 0) { this.homePage() }
        else if (index === 1) { this.toolsPage() }
        else if (index === 2) { this.historyPage() }
        else { this.profilePage() }
      }.width('100%').padding({ left: this.pagePadding(), right: this.pagePadding(), bottom: this.wide() ? 26 : 120 })
    }.id(`main-tab-${index}`).width('100%').height('100%')
      .contentStartOffset(56).contentEndOffset(24 + this.bottomInset)
      .enableScrollInteraction(true).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .scrollBar(BarState.Off).align(Alignment.Top)
      .onDidScroll((_x: number, _y: number, _state: ScrollState) => { this.updateTitleCollapse(index); })
  }
  @Builder
  sharedPrimaryTitleBar() {
    if (this.wide()) {
      this.primaryTitleBar(0)
    }
  }
  @Builder
  primaryTitleBar(index: number) {
    Row({ space: 12 }) {
      if (this.wide()) {
        LumiNavigation({ active: this.activeTab, onSelect: (selected: number) => { this.query = ''; this.selectTab(selected); } })
          .layoutWeight(1)
      } else {
        Row({ space: 7 }) {
          if (!this.titleCollapsed[index]) {
            Image($r('app.media.lumi_logo')).width(26).height(26).borderRadius(8)
          }
          Text(this.titleCollapsed[index] ? ['首页', '工具', '记录', '我的'][index] : 'LumiKit')
            .fontSize(this.titleCollapsed[index] ? 18 : 23).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).maxLines(1)
        }.layoutWeight(1)
      }
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        LumiIcon({ name: this.primaryTitleIndex(index) === 0 ? 'search' : this.primaryTitleIndex(index) === 3 ? 'info' : 'folder', iconSize: 21 })
      }.id(`primary-action-${this.primaryTitleIndex(index)}`).width(40).height(40).padding(0)
        .systemMaterial(this.immersiveSupported ? this.titleButtonMaterial : undefined)
        .accessibilityText(this.primaryTitleIndex(index) === 0 ? '搜索工具' : this.primaryTitleIndex(index) === 3 ? '使用说明' : '文件工作区')
        .onClick(() => {
          if (this.primaryTitleIndex(index) === 0) { this.query = ''; this.category = 'all'; this.favoriteOnly = false; this.selectTab(1); }
          else { this.openTool(this.primaryTitleIndex(index) === 3 ? 'help' : 'file-workspace'); }
        })
    }.id(`primary-title-${this.primaryTitleIndex(index)}`).width('100%').height('100%')
      .padding({ left: this.pagePadding(), right: this.pagePadding() })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
  @Builder
  primaryTabContent(index: number) {
    if (this.wide()) {
      this.tabPage(index)
    } else {
      Navigation() {
        this.tabPage(index)
      }.mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true)
        .title({ builder: () => { this.primaryTitleBar(index); }, height: 56 }, {
          barStyle: BarStyle.STACK,
          scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
        })
        .width('100%').height('100%').backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }
  @Builder
  dockItem(index: number, title: string, icon: string) {
    Column({ space: 2 }) {
      LumiIcon({ name: 'dock-' + icon, iconSize: 24, muted: this.activeTab !== index })
      Text(title).fontSize(11).maxLines(1).fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Medium)
        .lineHeight(14).fontColor(this.activeTab === index ? $r('app.color.brand') : $r('app.color.text_secondary'))
    }.id('nav-tab-' + index).width('100%').height('100%').padding({ bottom: 2 }).justifyContent(FlexAlign.Center)
      .scale(this.activeTab === index ? { x: 1.04, y: 1.04 } : { x: 1, y: 1 })
      .animation({ duration: this.reduceMotion ? 0 : 220, curve: this.reduceMotion ? Curve.Linear : this.tabSpring })
      .accessibilityText(title).accessibilitySelected(this.activeTab === index)
  }
  build() {
    Stack() {
      Navigation(this.pathStack) {
        Column() {
          if (!this.ready) {
            LumiLaunchScreen({ startupStep: this.startupStep, errorMessage: this.startupError,
              reduceMotion: this.reduceMotion, bottomInset: this.bottomInset, onRetry: () => { this.initialize(); } })
              .transition(TransitionEffect.OPACITY.animation({ duration: this.reduceMotion ? 0 : 180, curve: Curve.EaseOut }))
          } else {
            Tabs({ barPosition: BarPosition.End, index: this.activeTab, controller: this.tabsController,
              barModifier: this.wide() ? this.defaultBarModifier : this.phoneBarModifier }) {
              TabContent() { this.primaryTabContent(0) }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .tabBar(this.dockItem(0, '首页', 'home'))
              TabContent() { this.primaryTabContent(1) }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .tabBar(this.dockItem(1, '工具', 'tools'))
              TabContent() { this.primaryTabContent(2) }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .tabBar(this.dockItem(2, '记录', 'history'))
              TabContent() { this.primaryTabContent(3) }.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
                .tabBar(this.dockItem(3, '我的', 'profile'))
            }
            .height(LayoutPolicy.matchParent)
            .layoutWeight(1)
            .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .scrollable(false)
            .barMode(BarMode.Fixed)
            .barOverlap(!this.wide())
            .barBackgroundColor(this.immersiveSupported ? Color.Transparent : $r('app.color.dock_fallback'))
            .barHeight(this.wide() ? 0 : 60)
            .animationMode(this.reduceMotion ? AnimationMode.NO_ANIMATION : AnimationMode.CONTENT_FIRST_WITH_JUMP)
            .animationDuration(this.reduceMotion ? 0 : 260)
            .animationCurve(this.reduceMotion ? Curve.Linear : this.tabSpring)
            .barFloatingStyle(this.wide() ? undefined : {
              barBottomMargin: 12,
              barSideMargin: 24,
              maskColor: Color.Transparent,
              maskHeight: 0,
              systemMaterial: this.immersiveSupported ? this.dockMaterial : undefined
            })
            .onChange((index: number) => {
              if (index !== this.activeTab) { this.query = ''; this.activateTab(index); }
            })
            .onTabBarClick((index: number) => {
              if (index === this.activeTab) { this.tabScrollers[index].scrollEdge(Edge.Top); }
            })
            .width('100%')
          }
        }.width('100%').height('100%').backgroundColor(Color.Transparent)
      }
      .hideTitleBar(!this.wide() || !this.ready)
      .hideBackButton(true)
      .hideToolBar(true)
      .title({ builder: () => { this.sharedPrimaryTitleBar(); }, height: 56 }, {
        barStyle: BarStyle.STACK,
        scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
      })
      .mode(NavigationMode.Stack)
      .width('100%').height('100%').backgroundColor(Color.Transparent)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .width('100%').height('100%')
    .background($r('app.color.background'), {
      ignoresLayoutSafeAreaEdges: [LayoutSafeAreaEdge.ALL]
    })
    .onAreaChange((_old: Area, current: Area) => { this.viewportWidth = Number(current.width); })
  }
}
