import { OcrService } from '../ocr/OcrService';
import { LumiReceiptCandidates, receiptCandidates } from './ReceiptCandidates';
import { curves } from '@kit.ArkUI';
import { TextAreaPageScroll } from '../../core/TextAreaPageScroll';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { LumiHelpNavigation } from '../help/HelpNavigation';
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { StorageService } from '../../core/StorageService';
import { InventoryItem, LendingRecord, LocalAttachment, isValidDate, localDate, newLocalId, validInventoryItem } from './InventoryModels';
import { camera, cameraPicker } from '@kit.CameraKit';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { InventoryReminders, inventoryReminderPlans } from './InventoryReminders';
import { LumiRecordRouteParam } from '../../core/IncomingRequest';
import { InventoryFiles } from './InventoryFiles';

@Builder
export function inventoryBuilder() {
  InventoryPage()
}

@Component
export struct InventoryPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State private receipt: LumiReceiptCandidates = new LumiReceiptCandidates();
  @State private receiptText: string = '';
  @State private receiptPath: string = '';
  @State private showReceipt: boolean = false;
  @State private expandedDetails: boolean = false;
  @State private items: InventoryItem[] = [];
  @State private query: string = '';
  @State private category: string = '全部';
  @State private status: string = '在用';
  @State @Watch('resetPagePosition') private mode: string = 'list';
  @State private draft: InventoryItem = new InventoryItem();
  @State private dueDate: string = '';
  private recordId: string = '';
  private pendingCreate: boolean = false;
  private lastCategory: string = '未分类';
  @State private borrower: string = '';
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private reminderWarning: string = '';
  @State private calendarReminders: boolean = false;
  @State private message: string = '';
  private confirmingBack: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private readonly pageScroller: Scroller = new Scroller();
  private readonly inputScroll: TextAreaPageScroll = new TextAreaPageScroll();

  aboutToAppear(): void {
    this.load();
  }

  private resetPagePosition(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.pageScroller.scrollEdge(Edge.Top);
  }

  private async goBack(): Promise<void> {
    if (this.busy) { this.toast('请等待当前操作完成'); return; }
    if (this.confirmingBack) { return; }
    if (this.mode === 'edit') {
      const saved = this.items.find((item: InventoryItem) => item.id === this.draft.id);
      const changed = saved ? JSON.stringify(saved) !== JSON.stringify(this.draft) :
        this.draft.name.length > 0 || this.draft.brand.length > 0 || this.draft.model.length > 0 ||
        this.draft.category !== '未分类' || this.draft.purchaseDate.length > 0 || this.draft.price.length > 0 ||
        this.draft.warrantyDate.length > 0 || this.draft.channel.length > 0 || this.draft.notes.length > 0 ||
        this.draft.attachments.length > 0;
      if (changed) {
        this.confirmingBack = true;
        try {
          const result = await this.getUIContext().getPromptAction().showDialog({
            title: '放弃未保存的修改？', message: '返回后，这次对物品档案的修改将被丢弃。',
            buttons: [{ text: '继续编辑', color: '#66758A' }, { text: '放弃修改', color: '#D74747' }]
          });
          if (result.index !== 1) { return; }
        } catch (error) { return; }
        finally { this.confirmingBack = false; }
      }
      if (saved) { this.draft = JSON.parse(JSON.stringify(saved)) as InventoryItem; this.mode = 'detail'; }
      else { this.mode = 'list'; }
      this.message = '';
    } else if (this.mode === 'detail') { this.mode = 'list'; }
    else { this.pathStack.pop(); }
  }

  private async load(): Promise<void> {
    try {
      const items = JSON.parse(await StorageService.getValue('inventory.items', '[]')) as InventoryItem[];
      if (!Array.isArray(items) || !items.every(validInventoryItem)) { throw new Error('物品格式无效'); }
      this.items = items;
      this.lastCategory = await StorageService.getSetting('inventoryLastCategory', '未分类');
      this.calendarReminders = await StorageService.getSetting('inventoryReminderBackend', 'agent') === 'calendar';
      const selected = items.find((item: InventoryItem) => item.id === this.recordId);
      if (selected) { this.openItem(selected, 'detail'); }
      if (this.pendingCreate) { this.pendingCreate = false; this.createItem(); }
    } catch (error) { this.message = '物品暂时无法读取，请返回后重试。'; }
    this.ready = true;
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message });
  }

  private categories(): string[] {
    const categories: string[] = ['全部'];
    this.items.forEach((item: InventoryItem) => {
      if (!categories.includes(item.category)) { categories.push(item.category); }
    });
    return categories;
  }

  private currentLoan(item: InventoryItem): LendingRecord | undefined {
    return item.lending.find((loan: LendingRecord) => loan.returnedAt.length === 0);
  }

  private warranty(item: InventoryItem): string {
    if (!item.warrantyDate || item.archived || !isValidDate(item.warrantyDate)) { return ''; }
    const parts = item.warrantyDate.split('-').map((part: string) => Number(part));
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const days = Math.ceil((new Date(parts[0], parts[1] - 1, parts[2]).getTime() - today.getTime()) / 86400000);
    if (days < 0) { return '保修已到期'; }
    if (days <= 30) { return days === 0 ? '保修今日到期' : `保修剩余 ${days} 天`; }
    return '';
  }

  private visibleItems(): InventoryItem[] {
    const query = this.query.trim().toLowerCase();
    return this.items.filter((item: InventoryItem) => {
      const statusMatches = this.status === '已归档' ? item.archived : !item.archived;
      const loanMatches = this.status !== '借出' || this.currentLoan(item) !== undefined;
      return statusMatches && loanMatches && (this.category === '全部' || item.category === this.category) &&
        `${item.name} ${item.brand} ${item.model} ${item.notes}`.toLowerCase().includes(query);
    });
  }

  private warningCount(): number {
    return this.items.filter((item: InventoryItem) => this.warranty(item).length > 0).length;
  }

  private openItem(item: InventoryItem, mode: string): void {
    this.draft = JSON.parse(JSON.stringify(item)) as InventoryItem;
    this.borrower = ''; this.dueDate = '';
    this.message = '';
    this.mode = mode; this.expandedDetails = true; this.showReceipt = false;
  }

  private createItem(): void {
    this.draft = new InventoryItem(); this.expandedDetails = false; this.showReceipt = false; this.receiptText = ''; this.receiptPath = '';
    this.draft.category = this.lastCategory;
    this.draft.id = newLocalId('item');
    this.draft.createdAt = Date.now();
    this.message = '';
    this.mode = 'edit';
  }

  private async persist(next: InventoryItem[], history: string): Promise<boolean> {
    this.busy = true;
    try {
      await StorageService.setValue('inventory.items', JSON.stringify(next));
      this.items = JSON.parse(JSON.stringify(next)) as InventoryItem[];
      try { await InventoryReminders.sync(this.items, this.context()); this.reminderWarning = ''; }
      catch (error) { this.reminderWarning = '资料已保存；提醒尚未更新，可点击下方按钮重试或使用系统日历提醒。'; }
      try { await StorageService.addHistory('inventory', history, '物品档案已保存到本机'); } catch (error) {}
      return true;
    } catch (error) {
      this.toast('保存失败，请重试');
      return false;
    } finally { this.busy = false; }
  }

  private async save(): Promise<void> {
    if (!this.draft.name.trim()) { this.message = '请填写物品名称'; return; }
    if (this.draft.price && (!Number.isFinite(Number(this.draft.price)) || Number(this.draft.price) < 0)) {
      this.message = '价格需填写不小于 0 的数字'; return;
    }
    if ((this.draft.purchaseDate && !isValidDate(this.draft.purchaseDate)) ||
      (this.draft.warrantyDate && !isValidDate(this.draft.warrantyDate))) {
      this.message = '日期请使用 YYYY-MM-DD 格式'; return;
    }
    if (this.draft.warrantyReminderDate && !isValidDate(this.draft.warrantyReminderDate)) { this.message = '提醒日期请使用 YYYY-MM-DD'; return; }
    this.draft.name = this.draft.name.trim();
    this.draft.category = this.draft.category.trim() || '未分类';
    const next = this.items.filter((item: InventoryItem) => item.id !== this.draft.id);
    next.unshift(JSON.parse(JSON.stringify(this.draft)) as InventoryItem);
    if (await this.persist(next, '保存物品档案')) { this.lastCategory = this.draft.category; await StorageService.setSetting('inventoryLastCategory', this.lastCategory); this.mode = 'detail'; this.message = ''; this.toast('已保存'); }
  }

  private async saveStatus(): Promise<void> {
    const next = this.items.map((item: InventoryItem) => item.id === this.draft.id ? this.draft : item);
    if (await this.persist(next, '更新物品状态')) {
      this.draft = JSON.parse(JSON.stringify(this.draft)) as InventoryItem;
      this.toast('状态已更新');
    } else {
      const saved = this.items.find((item: InventoryItem) => item.id === this.draft.id);
      if (saved) { this.draft = JSON.parse(JSON.stringify(saved)) as InventoryItem; }
    }
  }

  private async lend(): Promise<void> {
    if (!this.borrower.trim()) { this.toast('请填写借用人'); return; }
    if (this.dueDate && !isValidDate(this.dueDate)) { this.toast('预计归还日期请使用 YYYY-MM-DD'); return; }
    const loan = new LendingRecord();
    loan.dueDate = this.dueDate;
    loan.id = newLocalId('loan');
    loan.borrower = this.borrower.trim();
    loan.lentAt = localDate(new Date());
    this.draft.lending = [loan].concat(this.draft.lending);
    await this.saveStatus();
    this.borrower = '';
  }

  private async returnItem(): Promise<void> {
    this.draft.lending = this.draft.lending.map((loan: LendingRecord) => {
      if (!loan.returnedAt) { loan.returnedAt = localDate(new Date()); }
      return loan;
    });
    await this.saveStatus();
  }

  private async deleteItem(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '删除物品', message: '删除后无法恢复该物品档案和借出记录。',
      buttons: [{ text: '取消', color: '#66758A' }, { text: '删除', color: '#D74747' }]
    });
    if (result.index !== 1) { return; }
    if (await this.persist(this.items.filter((item: InventoryItem) => item.id !== this.draft.id), '删除物品档案')) {
      this.mode = 'list';
    }
  }

  private duplicateItem(): void {
    const copy = JSON.parse(JSON.stringify(this.draft)) as InventoryItem;
    copy.id = newLocalId('item'); copy.name += '（副本）'; copy.createdAt = Date.now(); copy.archived = false;
    copy.lending = []; copy.warrantyReminderDate = ''; this.draft = copy; this.mode = 'edit';
  }
  private async capturePhoto(): Promise<void> {
    this.busy = true;
    try {
      const result = await cameraPicker.pick(this.context(), [cameraPicker.PickerMediaType.PHOTO], { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK });
      if (!result.resultUri) { return; }
      const files = await FileService.importUris(this.context(), [result.resultUri]);
      this.draft.attachments = this.draft.attachments.concat(files.map((file: WorkspaceFile): LocalAttachment =>
        ({ id: file.id, name: file.name, path: file.path, size: file.size })));
    } catch (error) { this.toast((error as Error).message || '拍照未完成'); }
    finally { this.busy = false; }
  }
  private async scanReceipt(useCamera: boolean): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      let files: WorkspaceFile[] = [];
      if (useCamera) {
        const result = await cameraPicker.pick(this.context(), [cameraPicker.PickerMediaType.PHOTO], { cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK });
        if (!result.resultUri) { return; }
        files = await FileService.importUris(this.context(), [result.resultUri]);
      } else { files = await FileService.pickFiles(this.context(), ['购买凭证图片|.png,.jpg,.jpeg,.webp,.heic'], 1); }
      if (!files.length) { return; }
      this.receiptPath = files[0].path; this.receiptText = ''; this.showReceipt = false;
      this.receiptText = await OcrService.recognize(this.receiptPath);
      this.receipt = receiptCandidates(this.receiptText); this.showReceipt = true;
      this.message = '';
    } catch (error) { this.message = (error as Error).message || '识别未完成，可手动填写'; }
    finally { this.busy = false; }
  }
  private async applyReceipt(): Promise<void> {
    if (this.receipt.purchaseDate && !isValidDate(this.receipt.purchaseDate)) { this.message = '请核对日期，使用 YYYY-MM-DD'; return; }
    if (this.receipt.price && (!Number.isFinite(Number(this.receipt.price)) || Number(this.receipt.price) < 0)) { this.message = '请核对购买金额'; return; }
    try {
      const file = (await FileService.list(this.context())).find((entry: WorkspaceFile) => entry.path === this.receiptPath);
      if (!file) { throw new Error('凭证文件不可用，请重新选择'); }
      const draft = JSON.parse(JSON.stringify(this.draft)) as InventoryItem;
      if (!draft.name.trim()) { draft.name = this.receipt.name.trim(); }
      if (!draft.purchaseDate) { draft.purchaseDate = this.receipt.purchaseDate; }
      if (!draft.price) { draft.price = this.receipt.price; }
      if (!draft.attachments.some((entry: LocalAttachment) => entry.path === file.path)) {
        draft.attachments = draft.attachments.concat([{ id: file.id, name: file.name, path: file.path, size: file.size } as LocalAttachment]);
      }
      this.draft = draft; this.showReceipt = false; this.expandedDetails = true; this.message = '';
      this.toast('已填入空白字段并附上凭证；点击保存物品后生效');
    } catch (error) { this.message = (error as Error).message; }
  }

  private async enableReminders(useCalendar: boolean = false): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      if (useCalendar) { await InventoryReminders.enableCalendar(this.context(), this.items); }
      else { await InventoryReminders.enable(this.context(), this.items); }
      this.calendarReminders = await StorageService.getSetting('inventoryReminderBackend', 'agent') === 'calendar';
      this.reminderWarning = '';
      const count = inventoryReminderPlans(this.items, Date.now()).length;
      this.toast(count ? count.toString() + ' 个到期提醒已预约，按设置日期上午 9 点提醒' : '暂无可预约的未来提醒，请先填写保修提醒或预计归还日期');
    } catch (error) {
      this.reminderWarning = useCalendar || this.calendarReminders ? '日历提醒未更新：' + (error as Error).message :
        '当前设备暂不能预约应用通知，可选择系统日历提醒。';
    } finally { this.busy = false; }
  }

  private async attach(): Promise<void> {
    this.busy = true;
    try {
      const attachments = await InventoryFiles.attach(this.context());
      this.draft.attachments = this.draft.attachments.concat(attachments);
    } catch (error) { this.toast((error as Error).message || '附件未能添加'); }
    finally { this.busy = false; }
  }

  private async exportAttachment(attachment: LocalAttachment): Promise<void> {
    try {
      if (await InventoryFiles.exportAttachment(this.context(), attachment)) { this.toast('附件已导出'); }
    } catch (error) { this.toast('附件导出失败，请重试'); }
  }

  private pickDate(isWarranty: boolean): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(1970, 0, 1), end: new Date(2100, 11, 31), selected: new Date(), lunar: false,
      onDateAccept: (value: Date) => {
        if (isWarranty) { this.draft.warrantyDate = localDate(value); }
        else { this.draft.purchaseDate = localDate(value); }
      }
    });
  }

  @Builder
  private field(label: string, value: string, placeholder: string, change: (value: string) => void) {
    Column({ space: 8 }) {
      Text(label).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_secondary'))
      TextInput({ text: value, placeholder: placeholder }).id('inventory-input-' + label).height(48).borderRadius(13)
        .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
        .onChange(change)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private itemCard(item: InventoryItem) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 14 }) {
        Text(item.name.substring(0, 1)).fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('app.color.brand'))
          .width(52).height(56).textAlign(TextAlign.Center).backgroundColor($r('app.color.brand_soft')).borderRadius(16)
        Column({ space: 7 }) {
          Text(item.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).maxLines(1)
          Text(`${item.category}${item.brand ? ` · ${item.brand}` : ''}${item.model ? ` ${item.model}` : ''}`)
            .fontSize(12).fontColor($r('app.color.text_secondary')).maxLines(1)
          if (this.warranty(item)) {
            Text(this.warranty(item)).fontSize(11).fontColor($r('app.color.error'))
          } else if (this.currentLoan(item)) {
            Text(`已借给 ${this.currentLoan(item)?.borrower}`).fontSize(11).fontColor($r('app.color.brand'))
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text('›').fontSize(26).fontColor($r('app.color.text_secondary'))
      }.width('100%')
    }.id('inventory-card-' + item.id).accessibilityText(item.name)
      .padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
      .onClick(() => this.openItem(item, 'detail'))
  }

  @Builder
  private listing() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 6 }) {
          Text('我的物品').fontSize(13).fontColor($r('app.color.text_secondary'))
          Text(`${this.items.filter((item: InventoryItem) => !item.archived).length}`)
            .fontSize(36).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 6 }) {
          Text('保修待留意').fontSize(13).fontColor($r('app.color.text_secondary'))
          Text(`${this.warningCount()}`).fontSize(36).fontWeight(FontWeight.Medium).fontColor($r('app.color.brand'))
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24)
      Button('＋ 新建物品').id('inventory-create').height(46).width('100%').fontSize(14)
        .backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(() => this.createItem())
      Search({ value: this.query, placeholder: '搜索名称、品牌、型号或备注' }).id('inventory-search').height(48)
        .backgroundColor($r('app.color.surface')).onChange((value: string) => { this.query = value; })
      Row({ space: 8 }) {
        ForEach(['在用', '借出', '已归档'], (status: string) => {
          Button(status, { type: ButtonType.Normal }).id('inventory-filter-' + status).height(38).layoutWeight(1).borderRadius(12).fontSize(13)
            .backgroundColor(this.status === status ? $r('app.color.brand') : $r('app.color.surface'))
            .fontColor(this.status === status ? $r('app.color.inverse_text') : $r('app.color.text_secondary'))
            .onClick(() => { this.status = status; })
        })
      }.width('100%')
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.categories(), (category: string) => {
            Button(category, { type: ButtonType.Normal }).height(34).borderRadius(10).fontSize(12)
              .backgroundColor(this.category === category ? $r('app.color.brand_soft') : $r('app.color.surface'))
              .fontColor(this.category === category ? $r('app.color.brand') : $r('app.color.text_secondary'))
              .onClick(() => { this.category = category; })
          })
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      if (!this.ready) {
        LoadingProgress().width(32).height(32).color($r('app.color.brand'))
      } else if (this.visibleItems().length === 0) {
        Column({ space: 12 }) {
          Text('一件物品，一段故事').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
          Text(this.items.length === 0 ? '记录购买、保修和借出信息\n从添加你的第一件物品开始' : '没有符合筛选条件的物品')
            .fontSize(13).lineHeight(22).textAlign(TextAlign.Center).fontColor($r('app.color.text_secondary'))
        }.padding({ top: 42, bottom: 44 }).width('100%')
      } else {
        ForEach(this.visibleItems(), (item: InventoryItem) => { this.itemCard(item) }, (item: InventoryItem) => JSON.stringify(item))
      }
    }.width('100%')
  }

  @Builder
  private editor() {
    Column({ space: 18 }) {
      Button('拍照添加物品照片').id('inventory-camera').width('100%').onClick(() => this.capturePhoto()).enabled(!this.busy)
      Row({ space: 8 }) {
        Button('拍摄购买凭证').id('receipt-camera').layoutWeight(1).fontSize(13).enabled(!this.busy).onClick(() => this.scanReceipt(true))
        Button('导入凭证识别').id('receipt-import').layoutWeight(1).fontSize(13).enabled(!this.busy).onClick(() => this.scanReceipt(false))
      }.width('100%')
      if (this.showReceipt) {
        Column({ space: 12 }) {
          Text('核对购买凭证').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          Image(fileUri.getUriFromPath(this.receiptPath)).width('100%').height(180).objectFit(ImageFit.Contain)
          Text('仅填入空白字段；保修期限由你填写。未能确定的信息留空。').fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
          this.field('候选商品名称', this.receipt.name, '未识别，可手动补充', (text: string) => { this.receipt.name = text; })
          this.field('候选购买日期', this.receipt.purchaseDate, 'YYYY-MM-DD，请核对交易日期', (text: string) => { this.receipt.purchaseDate = text; })
          this.field('候选金额', this.receipt.price, '请核对实付金额', (text: string) => { this.receipt.price = text; })
          Text(this.receiptText.slice(0, 4000)).fontSize(11).fontColor($r('app.color.text_secondary')).copyOption(CopyOptions.InApp).maxLines(12)
          Button('核对完成，填入空白字段').id('receipt-apply').enabled(!this.busy).onClick(() => this.applyReceipt())
          Button('放弃这次识别', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { this.showReceipt = false; })
        }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
      }
      Column({ space: 18 }) {
        this.field('物品名称 *', this.draft.name, '例如：随身相机', (value: string) => { this.draft.name = value; })
        this.field('分类', this.draft.category, '填写任意名称即可创建分类', (value: string) => { this.draft.category = value; })
        Button(this.expandedDetails ? '收起详细信息' : '补充购买、保修与其他信息', { buttonStyle: ButtonStyleMode.TEXTUAL }).onClick(() => { this.expandedDetails = !this.expandedDetails; })
        if (this.expandedDetails) {
        this.field('品牌', this.draft.brand, '物品品牌', (value: string) => { this.draft.brand = value; })
        this.field('型号', this.draft.model, '物品型号', (value: string) => { this.draft.model = value; })
        this.field('购买价格 / 元', this.draft.price, '0.00', (value: string) => { this.draft.price = value; })
        this.field('购买日期', this.draft.purchaseDate, 'YYYY-MM-DD', (value: string) => { this.draft.purchaseDate = value; })
        Button('选择购买日期').fontSize(12).height(34).fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_soft')).onClick(() => this.pickDate(false))
        this.field('保修截止日期', this.draft.warrantyDate, 'YYYY-MM-DD', (value: string) => { this.draft.warrantyDate = value; })
        Button('选择保修日期').fontSize(12).height(34).fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_soft')).onClick(() => this.pickDate(true))
        this.field('保修提醒日期', this.draft.warrantyReminderDate || '', 'YYYY-MM-DD，留空不提醒', (value: string) => { this.draft.warrantyReminderDate = value; })
        Text('仅预约尚未到来的日期上午 9 点；当天 9 点后请选择下一天。可在详情启用通知。').fontSize(11).fontColor($r('app.color.text_secondary'))
        this.field('购买渠道', this.draft.channel, '商店或平台名称', (value: string) => { this.draft.channel = value; })
        Text('备注').fontSize(13).fontColor($r('app.color.text_secondary'))
        TextArea({ text: this.draft.notes, placeholder: '记录使用心得、序列号或其他信息' }).id('inventory-notes').attributeModifier(this.inputScroll).height(110)
          .backgroundColor($r('app.color.soft_surface')).borderRadius(13).onChange((value: string) => { this.draft.notes = value; })
        }
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
      this.attachmentSection(true)
      if (this.message) { Text(this.message).fontSize(13).fontColor($r('app.color.error')).width('100%') }
      Button(this.busy ? '正在保存…' : '保存物品').id('inventory-save').height(50).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text'))
        .enabled(!this.busy).onClick(() => this.save())
    }
  }

  @Builder
  private information(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(13).fontColor($r('app.color.text_secondary')).width(86)
      Text(value || '未填写').fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
    }.width('100%').alignItems(VerticalAlign.Top)
  }

  @Builder
  private attachmentSection(editing: boolean) {
    Column({ space: 14 }) {
      Row() {
        Text('图片与附件').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).layoutWeight(1)
        if (editing) {
          Button('＋ 添加').fontSize(12).height(34).fontColor($r('app.color.brand')).backgroundColor($r('app.color.brand_soft'))
            .enabled(!this.busy).onClick(() => this.attach())
        }
      }.width('100%')
      if (this.draft.attachments.length === 0) {
        Text('可添加图片、发票 PDF 等文件，保存在本机').fontSize(12).fontColor($r('app.color.text_secondary'))
      }
      ForEach(this.draft.attachments, (attachment: LocalAttachment) => {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text(attachment.name).fontSize(13).fontColor($r('app.color.text_primary')).maxLines(2)
            Text(`${Math.ceil(attachment.size / 1024)} KB · 本地附件`).fontSize(11).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button(editing ? '移除' : '导出').fontSize(12).height(34).backgroundColor($r('app.color.soft_surface'))
            .fontColor($r('app.color.brand')).onClick(() => {
              if (editing) { this.draft.attachments = this.draft.attachments.filter((entry: LocalAttachment) => entry.id !== attachment.id); }
              else { this.exportAttachment(attachment); }
            })
        }.width('100%')
      }, (attachment: LocalAttachment) => attachment.id)
    }.width('100%').padding(20).backgroundColor($r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private detail() {
    Column({ space: 18 }) {
      Column({ space: 18 }) {
        Row() {
          Column({ space: 8 }) {
            Text(this.draft.category).fontSize(12).fontColor($r('app.color.brand'))
            Text(this.draft.name).id('inventory-detail-name').fontSize(26).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Button('编辑').id('inventory-edit').height(38).fontColor($r('app.color.brand')).backgroundColor($r('app.color.brand_soft'))
            .onClick(() => this.openItem(this.draft, 'edit'))
        }.width('100%')
        if (this.warranty(this.draft)) {
          Text(`${this.warranty(this.draft)} · ${this.draft.warrantyDate}`).fontSize(13).fontColor($r('app.color.error'))
        }
        this.information('品牌 / 型号', `${this.draft.brand} ${this.draft.model}`.trim())
        this.information('购买日期', this.draft.purchaseDate)
        this.information('购买价格', this.draft.price ? `¥ ${this.draft.price}` : '')
        this.information('保修截止', this.draft.warrantyDate)
        this.information('购买渠道', this.draft.channel)
        this.information('备注', this.draft.notes)
      }.padding(22).width('100%').backgroundColor($r('app.color.surface')).borderRadius(24).alignItems(HorizontalAlign.Start)
      Button('复制此物品').id('inventory-duplicate').width('100%').onClick(() => this.duplicateItem())
      if (this.reminderWarning) { Text(this.reminderWarning).fontSize(12).fontColor($r('app.color.error')).width('100%') }
      Button(this.calendarReminders ? '更新日历提醒' : '启用 / 更新到期通知').id('inventory-enable-reminders')
        .width('100%').enabled(!this.busy).onClick(() => this.enableReminders())
      if (!this.calendarReminders) {
        Button('使用系统日历提醒').id('inventory-calendar-reminders').width('100%').enabled(!this.busy)
          .onClick(() => this.enableReminders(true))
      }
      Text(this.calendarReminders ? '到期提醒已使用本机「集萤到期提醒」日历；点击通知打开系统日历。修改日期、归还或归档后会同步更新。' :
        '应用通知不可用时，可授权系统日历预约提醒；日历通知会打开系统日历。')
        .fontSize(11).fontColor($r('app.color.text_secondary')).width('100%')
      this.attachmentSection(false)
      Column({ space: 14 }) {
        Text('借出记录').fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
        if (this.currentLoan(this.draft)) {
          Text(`借给 ${this.currentLoan(this.draft)?.borrower} · ${this.currentLoan(this.draft)?.lentAt} · 预计归还 ${this.currentLoan(this.draft)?.dueDate || '未设置'}`)
            .fontSize(14).fontColor($r('app.color.brand'))
          Button('确认已归还').id('inventory-return').height(42).width('100%').backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).enabled(!this.busy)
            .onClick(() => this.returnItem())
        } else if (!this.draft.archived) {
          TextInput({ text: this.borrower, placeholder: '填写借用人' }).id('inventory-borrower').height(46).backgroundColor($r('app.color.soft_surface'))
            .onChange((value: string) => { this.borrower = value; })
          this.field('预计归还日期', this.dueDate, 'YYYY-MM-DD，留空不提醒', (value: string) => { this.dueDate = value; })
          Button('记录借出').id('inventory-lend').height(42).width('100%').fontColor($r('app.color.brand')).backgroundColor($r('app.color.brand_soft'))
            .enabled(!this.busy).onClick(() => this.lend())
        }
        ForEach(this.draft.lending.filter((loan: LendingRecord) => loan.returnedAt.length > 0), (loan: LendingRecord) => {
          Text(`${loan.borrower} · ${loan.lentAt} 借出 / ${loan.returnedAt} 归还`)
            .fontSize(12).fontColor($r('app.color.text_secondary'))
        }, (loan: LendingRecord) => loan.id)
        if (this.draft.lending.length === 0) {
          Text('还没有借出记录').fontSize(12).fontColor($r('app.color.text_secondary'))
        }
      }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22).alignItems(HorizontalAlign.Start)
      Row({ space: 12 }) {
        Button(this.draft.archived ? '恢复在用' : '归档物品').id('inventory-archive').height(46).layoutWeight(1)
          .backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).enabled(!this.busy)
          .onClick(() => { this.draft.archived = !this.draft.archived; this.saveStatus(); })
        Button('删除物品').id('inventory-delete').height(46).layoutWeight(1).backgroundColor($r('app.color.surface'))
          .fontColor($r('app.color.error')).enabled(!this.busy).onClick(() => this.deleteItem())
      }.width('100%')
    }
  }

  @Builder
  private pageTitleBar() {
    LumiBackHeader({ title: this.mode === 'edit' ? '编辑物品' : this.mode === 'detail' ? '物品档案' : '物品管理',
      onBack: () => { this.goBack(); }, showTutorial: true, tutorialEnabled: !this.busy,
      onTutorial: () => { LumiHelpNavigation.open(this.pathStack, 'inventory'); } })
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
          else if (this.mode === 'edit') { Column() { this.editor() }.width('100%').transition(this.modeTransition()) }
          else { Column() { this.detail() }.width('100%').transition(this.modeTransition()) }
          if (this.message && this.mode !== 'edit') { Text(this.message).fontSize(13).fontColor($r('app.color.error')).padding(16) }
        }.id('inventory-page-' + this.mode).width('100%').padding({ left: 20, right: 20, top: 12, bottom: 36 + this.bottomInset })
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
      this.pathStack = context.pathStack; const param = context.pathInfo.param as LumiRecordRouteParam;
      if (param?.createNew) { if (this.ready) { this.createItem(); } else { this.pendingCreate = true; } }
      if (param?.recordId) { this.recordId = param.recordId; const selected = this.items.find((item: InventoryItem) => item.id === this.recordId); if (selected) { this.openItem(selected, 'detail'); } }
    })
    .onBackPressed(() => { this.goBack(); return true; })
    .backgroundColor($r('app.color.background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
