import { TextAreaPageScroll } from '../../core/TextAreaPageScroll';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { LumiHelpNavigation } from '../help/HelpNavigation';
import { common } from '@kit.AbilityKit';
import { LumiXlsxSheet } from './XlsxParser';
import { readXlsx } from './XlsxService';
import { ChartExport } from './ChartExport';
import { taskpool } from '@kit.ArkTS';
import { FileService, WorkspaceFile } from '../../core/FileService';
import { StorageService } from '../../core/StorageService';
import { DataEngine, DataTable, NumericSummary, GroupSummary } from '../files/DataEngine';
import { EcosystemBridge } from '../../core/EcosystemBridge';

interface AnalysisProject { id: string; name: string; csv: string; savedAt: number; }

@Concurrent
function parseTable(text: string): DataTable { return DataEngine.parseCSV(text); }

export class AnalyticsRouteParam {
  filePath: string = '';
}

@Builder
export function analyticsBuilder() {
  AnalyticsPage()
}

@Component
export struct AnalyticsPage {
  @StorageProp('lumiBottomInset') bottomInset: number = 0;
  @State sheets: LumiXlsxSheet[] = [];
  @State sheetIndex: number = 0;
  @State input: string = '';
  @State table: DataTable = { headers: [], rows: [] };
  @State source: string = '未命名分析';
  @State field: number = 0;
  @State numeric: number = 0;
  @State filter: string = '';
  @State stats: NumericSummary = { count: 0, empty: 0, sum: 0, mean: 0, min: 0, max: 0 };
  @State groups: GroupSummary[] = [];
  @State projects: AnalysisProject[] = [];
  @State chartType: number = 0;
  @State metric: number = 0;
  @State message: string = '';
  @State isError: boolean = false;
  @State busy: boolean = false;
  @State showInput: boolean = true;
  @State page: number = 0;
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private original: DataTable = { headers: [], rows: [] };
  private readonly colors: string[] = ['#3978F6','#6A98FF','#9AB9FF','#72C7D4','#517CAE','#A3D7DE','#9AABDE','#C0D1F4'];
  private initialFilePath: string = '';
  private pathStack: NavPathStack = new NavPathStack();
  private readonly pageScroller: Scroller = new Scroller();
  private readonly inputScroll: TextAreaPageScroll = new TextAreaPageScroll();

  aboutToAppear(): void { this.loadProjects(); this.loadInitial(); }
  private async loadInitial(): Promise<void> {
    if(!this.initialFilePath){return;}
    try{
      const library = await FileService.list(this.ctx());
      const file = library.find((entry: WorkspaceFile) => entry.path === this.initialFilePath);
      if(!file){return;}
      this.initialFilePath = ''; await this.importWorkspaceFile(file);
    }catch(error){this.error(error as Error);}
  }

  private ctx(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private error(error: Error): void { this.message = error.message || '分析失败，请检查数据'; this.isError = true; }
  private async loadProjects(): Promise<void> {
    try { this.projects = JSON.parse(await StorageService.getValue('analytics-projects','[]')) as AnalysisProject[]; } catch (_) { this.projects = []; }
  }
  private async importFile(): Promise<void> {
    if (this.busy) { return; }
    try { const files = await FileService.pickFiles(this.ctx(), ['表格数据|.csv,.xlsx'], 1); if (files.length) { await this.importWorkspaceFile(files[0]); } }
    catch (error) { this.error(error as Error); }
  }
  private async importWorkspaceFile(file: WorkspaceFile): Promise<void> {
    this.busy = true;
    try {
      FileService.assertOwned(this.ctx(), file.path);
      this.source = file.name.replace(/\.(csv|xlsx)$/i, '');
      if (file.name.toLowerCase().endsWith('.xlsx')) {
        this.sheets = await taskpool.execute(readXlsx, file.path) as LumiXlsxSheet[];
        this.sheetIndex = Math.max(0, this.sheets.findIndex((sheet: LumiXlsxSheet) => sheet.csv.length > 0));
        this.input = this.sheets[this.sheetIndex].csv;
      } else { this.sheets = []; this.input = await FileService.readText(this.ctx(), file.path); }
      await this.parse();
    } catch (error) { this.error(error as Error); } finally { this.busy = false; }
  }
  private async selectSheet(index: number): Promise<void> {
    if (this.busy || !this.sheets[index]) { return; }
    this.sheetIndex = index; this.input = this.sheets[index].csv; await this.parse();
  }
  private async exportChart(): Promise<void> {
    if (this.busy) { return; } this.busy = true;
    try {
      const path = await ChartExport.create(this.ctx(), this.getUIContext(), this.source, this.table.headers[this.field],
        this.metric === 0 ? '记录数' : this.table.headers[this.numeric] + '合计', this.groups, this.chartType, this.metric === 1);
      await FileService.exportFile(this.ctx(), path, FileService.cleanName(this.source) + '_图表.png');
      this.message = '1200 × 900 图表已导出，工作区保留副本'; this.isError = false;
    } catch (error) { this.error(error as Error); } finally { this.busy = false; }
  }
  private async parse(): Promise<void> {
    this.busy = true;
    try {
      const table = await taskpool.execute(parseTable, this.input) as DataTable;
      this.table = table; this.original = { headers:table.headers.slice(), rows:table.rows.map((row:string[])=>row.slice()) };
      this.field=0; this.numeric=Math.max(0,table.headers.findIndex((_header:string,index:number)=>DataEngine.summary(table,index).count>0));
      this.showInput=false; this.page=0; this.filter=''; this.recalculate();
      this.message='已解析 '+table.rows.length.toString()+' 行、'+table.headers.length.toString()+' 列'; this.isError=false;
    } catch (error) { this.error(error as Error); } finally { this.busy=false; }
  }
  private recalculate(): void {
    this.stats=DataEngine.summary(this.table,this.numeric);
    this.groups=DataEngine.groups(this.table,this.field,this.numeric);
    this.drawChart();
  }
  private applyRows(rows:string[][],detail:string): void {
    this.table={headers:this.table.headers.slice(),rows:rows}; this.page=0; this.recalculate(); this.message=detail+' · 当前 '+rows.length.toString()+' 行'; this.isError=false;
  }
  private sort(ascending:boolean):void {
    const rows=this.table.rows.slice();
    const numeric=rows.some((row:string[])=>row[this.field].trim()!=='')&&rows.every((row:string[])=>row[this.field].trim()===''||Number.isFinite(Number(row[this.field])));
    rows.sort((a:string[],b:string[])=>{
      const av=a[this.field];const bv=b[this.field];
      if(numeric&&av.trim()===''){return bv.trim()===''?0:1;}
      if(numeric&&bv.trim()===''){return -1;}
      const comparison=numeric?Number(av)-Number(bv):av.localeCompare(bv);
      return ascending?comparison:-comparison;
    });
    this.applyRows(rows,ascending?'已升序排列':'已降序排列');
  }
  private deduplicate():void {
    const seen=new Set<string>();
    const rows=this.table.rows.filter((row:string[])=>{const key=JSON.stringify(row);if(seen.has(key)){return false;}seen.add(key);return true;});
    this.applyRows(rows,'已移除 '+(this.table.rows.length-rows.length).toString()+' 条整行重复记录');
  }
  private filterRows():void {
    this.applyRows(this.table.rows.filter((row:string[])=>row[this.field].toLowerCase().includes(this.filter.toLowerCase())),'已按字段筛选');
  }
  private restore():void { this.applyRows(this.original.rows.map((row:string[])=>row.slice()),'已恢复导入数据');this.filter=''; }
  private async export(format:string,grouped:boolean=false):Promise<void> {
    try {
      let table=this.table;
      if(grouped){table={headers:[this.table.headers[this.field],'记录数',this.table.headers[this.numeric]+'合计'],rows:this.groups.map((group:GroupSummary)=>[group.label,group.count.toString(),group.sum.toString()])};}
      const content=format==='csv'?DataEngine.csv(table):DataEngine.json(table);
      const name=FileService.cleanName(this.source)+(grouped?'_分组汇总':'_清洗结果')+'.'+format;
      const path=await FileService.writeText(this.ctx(),name,content);
      await FileService.exportFile(this.ctx(),path,name);
      await StorageService.addHistory('analytics','本地数据分析',table.rows.length.toString()+' 行 · '+name,path);
      this.message='已导出 '+name;this.isError=false;
    }catch(error){this.error(error as Error);}
  }
  private async saveProject():Promise<void> {
    try{
      const project:AnalysisProject={id:Date.now().toString(),name:this.source||'未命名分析',csv:DataEngine.csv(this.table),savedAt:Date.now()};
      const projects=this.projects.slice();projects.unshift(project);this.projects=projects.slice(0,10);
      await StorageService.setValue('analytics-projects',JSON.stringify(this.projects));
      await StorageService.addHistory('analytics','保存分析项目',project.name);
      this.message='已保存分析项目，可从本页重新打开';this.isError=false;
    }catch(error){this.error(error as Error);}
  }
  private async shareReportToLexiNote():Promise<void> {
    if(this.busy || this.table.headers.length === 0){return;}
    try{
      const reportTitle = (this.source || '未命名分析') + '_数据分析报告';
      const md = EcosystemBridge.buildAnalyticsReportMarkdown(this.source, this.table, this.field, this.numeric, this.stats, this.groups);
      await EcosystemBridge.shareMarkdownToLexiNote(this.ctx(), reportTitle, md, 'analytics', '导出数据分析报告到知萤');
      this.message = '分析报告已生成并保存在工作区，可在分享面板选择「知萤」';
      this.isError = false;
    }catch(error){this.error(error as Error);}
  }
  private chartValue(group:GroupSummary):number{return this.metric===0?group.count:group.sum;}
  private drawChart():void {
    const ctx=this.canvas;const w=ctx.width;const h=ctx.height;
    if(w<=0||h<=0){return;}ctx.clearRect(0,0,w,h);
    const data=this.groups.slice(0,8);if(data.length===0){return;}
    const values=data.map((group:GroupSummary)=>this.chartValue(group));
    const max=Math.max(1,...values.map((value:number)=>Math.abs(value)));
    ctx.font='11vp sans-serif';ctx.textBaseline='middle';
    if(this.chartType===3){
      if(values.some((value:number)=>value<0)){ctx.fillStyle='#64748B';ctx.fillText('饼图需要非负值，请切换为记录数。',12,36);return;}
      const total=values.reduce((sum:number,value:number)=>sum+value,0);if(total<=0){return;}
      let angle=-Math.PI/2;const radius=Math.min(w/2-15,90);const x=w/2;const y=105;
      data.forEach((group:GroupSummary,index:number)=>{const next=angle+values[index]/total*Math.PI*2;ctx.beginPath();ctx.moveTo(x,y);ctx.arc(x,y,radius,angle,next);ctx.closePath();ctx.fillStyle=this.colors[index];ctx.fill();angle=next;});
      return;
    }
    if(this.chartType===0){
      const rowHeight=Math.min(30,(h-12)/data.length);const center=values.some((value:number)=>value<0)?w*0.6:105;
      data.forEach((group:GroupSummary,index:number)=>{const y=12+index*rowHeight;ctx.fillStyle='#64748B';ctx.fillText((group.label||'（空值）').slice(0,8),0,y+8);const bar=(w-center-45)*values[index]/max;ctx.fillStyle=this.colors[index];ctx.fillRect(Math.min(center,center+bar),y,Math.max(1,Math.abs(bar)),16);ctx.fillStyle='#3A4B68';ctx.fillText(this.formatNumber(values[index]),Math.max(center,center+bar)+5,y+8);});
      return;
    }
    const left=22;const top=20;const plotW=w-40;const plotH=h-62;const hasNegative=values.some((value:number)=>value<0);const baseline=hasNegative?top+plotH/2:top+plotH;const scale=(hasNegative?plotH/2:plotH)/max;
    ctx.strokeStyle='#D9E4F2';ctx.beginPath();ctx.moveTo(left,baseline);ctx.lineTo(left+plotW,baseline);ctx.stroke();
    if(this.chartType===2){ctx.strokeStyle='#3978F6';ctx.lineWidth=2;ctx.beginPath();values.forEach((value:number,index:number)=>{const x=left+plotW*(index+0.5)/values.length;const y=baseline-value*scale;if(index===0){ctx.moveTo(x,y);}else{ctx.lineTo(x,y);}});ctx.stroke();}
    data.forEach((group:GroupSummary,index:number)=>{const x=left+plotW*(index+0.5)/data.length;const y=baseline-values[index]*scale;ctx.fillStyle=this.colors[index];if(this.chartType===1){ctx.fillRect(x-10,Math.min(y,baseline),20,Math.max(1,Math.abs(y-baseline)));}else{ctx.beginPath();ctx.arc(x,y,4,0,Math.PI*2);ctx.fill();}ctx.fillStyle='#64748B';ctx.textAlign='center';ctx.fillText((group.label||'（空值）').slice(0,4),x,h-24);ctx.fillText(this.formatNumber(values[index]),x,Math.max(8,y-10));});ctx.textAlign='left';
  }
  private formatNumber(value:number):string{return Number.isInteger(value)?value.toString():value.toFixed(2);}
  private sample():void{this.input='学院,月份,金额\n设计学院,1月,128\n计算机学院,1月,256\n设计学院,2月,198\n商学院,2月,180\n计算机学院,3月,320\n商学院,3月,220\n设计学院,3月,160';this.source='学院数据示例';this.parse();}
  @Builder
  private statCard(label:string,value:string){Column({space:6}){Text(value).id('analytics-stat-value-'+label).fontSize(23).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand'));Text(label).fontSize(11).fontColor($r('app.color.text_secondary'));}.layoutWeight(1).padding({top:17,bottom:17}).backgroundColor($r('app.color.surface')).borderRadius(17)}

  @Builder
  private pageTitleBar() {
    LumiBackHeader({ title: '本地数据分析', onBack: () => { this.pathStack.pop(); },
      showTutorial: true, tutorialEnabled: !this.busy,
      onTutorial: () => { LumiHelpNavigation.open(this.pathStack, 'analytics'); } })
  }

  build(){
    NavDestination(){
      Scroll(this.pageScroller){
        Column({space:18}){
          Column({space:7}){Text('让数据，说得更清楚。').fontSize(25).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'));Text('CSV / Excel 导入、清洗、汇总与图表，都在本机完成。').fontSize(12).fontColor($r('app.color.text_secondary'));}.alignItems(HorizontalAlign.Start).width('100%')
          Row({space:10}){Button('＋ 导入 CSV / Excel').id('analytics-import').height(48).layoutWeight(1).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(()=>this.importFile()).enabled(!this.busy);Button('粘贴数据').id('analytics-input-toggle').height(48).layoutWeight(1).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(()=>{this.showInput=!this.showInput;});}.width('100%')
          if (this.sheets.length > 0) {
            Select(this.sheets.map((sheet: LumiXlsxSheet): SelectOption => ({ value: sheet.name }))).id('analytics-sheet-select').selected(this.sheetIndex).value(this.sheets[this.sheetIndex].name).onSelect((index: number) => { this.selectSheet(index); }).width('100%')
            Text('Excel 读取已保存的公式计算值，不执行公式；首个非空行作为字段名。切换工作表会重新载入数据。').fontSize(11).lineHeight(18).fontColor($r('app.color.text_secondary'))
          }
          if(this.showInput){
            TextArea({text:this.input,placeholder:'首行为字段名，以逗号分隔\n学院,人数\n设计学院,28\n计算机学院,42'}).id('analytics-input').attributeModifier(this.inputScroll).height(200).fontSize(14).backgroundColor($r('app.color.surface')).fontColor($r('app.color.text_primary')).borderRadius(18).onChange((value:string)=>{this.input=value;})
            Row({space:10}){Button(this.busy?'正在解析…':'解析数据').id('analytics-parse').height(44).layoutWeight(1).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(()=>this.parse()).enabled(!this.busy);Button('体验示例').id('analytics-sample').height(44).layoutWeight(1).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.sample());}.width('100%')
            Text('UTF-8 CSV · 最多 4 MB / 20,000 行 / 100 列，空值为去除首尾空白后的空字符串。').fontSize(11).fontColor($r('app.color.text_secondary')).lineHeight(18).width('100%')
          }
          if(this.message){Text(this.message).id('analytics-message').fontSize(13).fontColor(this.isError?$r('app.color.error'):$r('app.color.success')).padding(14).width('100%').backgroundColor($r('app.color.surface')).borderRadius(14)}
          if(this.table.headers.length>0){
            TextInput({text:this.source,placeholder:'分析项目名称'}).id('analytics-project-name-input').fontSize(16).fontWeight(FontWeight.Medium).backgroundColor($r('app.color.surface')).onChange((value:string)=>{this.source=value;})
            Row({space:10}){this.statCard('数据行',this.table.rows.length.toString());this.statCard('字段',this.table.headers.length.toString());this.statCard('空单元格',this.table.rows.reduce((sum:number,row:string[])=>sum+row.filter((value:string)=>value.trim()==='').length,0).toString());}.width('100%')
            Column({space:14}){
              Text('01  数据整理').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              Select(this.table.headers.map((header:string):SelectOption=>({value:header}))).id('analytics-field-select').selected(this.field).value(this.table.headers[this.field]).onSelect((index:number)=>{this.field=index;this.recalculate();}).width('100%')
              Row({space:8}){Button('升序').id('analytics-sort-asc').layoutWeight(1).height(36).fontSize(12).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.sort(true));Button('降序').id('analytics-sort-desc').layoutWeight(1).height(36).fontSize(12).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.sort(false));Button('整行去重').id('analytics-deduplicate').layoutWeight(1).height(36).fontSize(12).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.deduplicate());}.width('100%')
              Row({space:8}){TextInput({text:this.filter,placeholder:'筛选：字段包含…'}).id('analytics-filter-input').layoutWeight(1).fontSize(13).backgroundColor($r('app.color.soft_surface')).onChange((value:string)=>{this.filter=value;});Button('应用').id('analytics-filter-apply').height(40).fontSize(12).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(()=>this.filterRows());}.width('100%')
              Row({space:8}){Button('仅看此列空值').id('analytics-null-only').height(34).fontSize(11).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_secondary')).onClick(()=>this.applyRows(this.table.rows.filter((row:string[])=>row[this.field].trim()===''),'已筛出空值'));Button('移除空白行').id('analytics-remove-blank').height(34).fontSize(11).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_secondary')).onClick(()=>this.applyRows(this.table.rows.filter((row:string[])=>row.some((value:string)=>value.trim()!=='')),'已移除空白行'));}.width('100%')
              Button('恢复本次导入数据').id('analytics-restore').height(32).fontSize(12).backgroundColor(Color.Transparent).fontColor($r('app.color.brand')).onClick(()=>this.restore())
            }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
            Column({space:12}){
              Row(){Text('数据预览').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).layoutWeight(1);Text('第 '+(this.page+1).toString()+' 页').fontSize(11).fontColor($r('app.color.text_secondary'));}.width('100%')
              Scroll(){Column({space:0}){Row(){ForEach(this.table.headers,(header:string)=>{Text(header).width(122).fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand')).padding(10)},(header:string)=>header)}.backgroundColor($r('app.color.brand_soft'));ForEach(this.table.rows.slice(this.page*12,this.page*12+12),(row:string[],index:number)=>{Row(){ForEach(row,(value:string,columnIndex:number)=>{Text(value||'—').id('analytics-cell-'+(this.page*12+index).toString()+'-'+columnIndex.toString()).width(122).height(40).maxLines(1).textOverflow({overflow:TextOverflow.Ellipsis}).fontSize(12).fontColor($r('app.color.text_primary')).padding(10)});}.id('analytics-table-row-'+(this.page*12+index).toString()).backgroundColor(index%2===0?$r('app.color.surface'):$r('app.color.soft_surface'));},(rowValue:string[],rowIndex:number)=>'row-'+(this.page*12+rowIndex).toString()+'-'+JSON.stringify(rowValue));}}.id('analytics-table-scroll').scrollable(ScrollDirection.Horizontal).width('100%')
                .height(42 + Math.min(12, Math.max(0, this.table.rows.length - this.page * 12)) * 40)
              Row({space:10}){Button('上一页').fontSize(12).height(32).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).enabled(this.page>0).onClick(()=>{this.page--;});Button('下一页').fontSize(12).height(32).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).enabled((this.page+1)*12<this.table.rows.length).onClick(()=>{this.page++;});}.width('100%')
            }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
            Column({space:14}){
              Text('02  数值统计').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              Select(this.table.headers.map((header:string):SelectOption=>({value:header}))).id('analytics-numeric-select').selected(this.numeric).value(this.table.headers[this.numeric]).onSelect((index:number)=>{this.numeric=index;this.recalculate();}).width('100%')
              Text('有效数值 '+this.stats.count.toString()+'  ·  空值 '+this.stats.empty.toString()+'  ·  非数值 '+(this.table.rows.length-this.stats.count-this.stats.empty).toString()).id('analytics-stats-summary').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
              Row({space:10}){this.statCard('求和',this.formatNumber(this.stats.sum));this.statCard('平均值',this.stats.count>0?this.formatNumber(this.stats.mean):'—');}.width('100%')
              Row({space:10}){this.statCard('最小值',this.stats.count>0?this.formatNumber(this.stats.min):'—');this.statCard('最大值',this.stats.count>0?this.formatNumber(this.stats.max):'—');}.width('100%')
              Text('空值与非数值不参与数值统计，原始单元格内容保持不变。').fontSize(11).fontColor($r('app.color.text_secondary')).lineHeight(18)
            }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
            Column({space:14}){
              Text('03  分组与图表').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
              Text('按「'+this.table.headers[this.field]+'」分组，共 '+this.groups.length.toString()+' 组').id('analytics-group-summary').fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
              Row({space:8}){Select([{value:'条形图'},{value:'柱状图'},{value:'折线图'},{value:'饼图'}]).id('analytics-chart-type').selected(this.chartType).value(['条形图','柱状图','折线图','饼图'][this.chartType]).onSelect((index:number)=>{this.chartType=index;this.drawChart();}).layoutWeight(1);Select([{value:'记录数'},{value:'数值合计'}]).id('analytics-chart-metric').selected(this.metric).value(this.metric===0?'记录数':'数值合计').onSelect((index:number)=>{this.metric=index;this.drawChart();}).layoutWeight(1);}.width('100%')
              Canvas(this.canvas).id('analytics-chart').width('100%').height(245).onReady(()=>this.drawChart()).onAreaChange(()=>this.drawChart())
              ForEach(this.groups.slice(0,8),(group:GroupSummary,index:number)=>{Row({space:8}){Circle().width(7).height(7).fill(this.colors[index]);Text(group.label||'（空值）').fontSize(12).fontColor($r('app.color.text_primary')).layoutWeight(1).maxLines(1);Text(group.count.toString()+' 条 · '+this.formatNumber(group.sum)).id('analytics-group-value-'+group.label).fontSize(11).fontColor($r('app.color.text_secondary'));}.width('100%')},(group:GroupSummary)=>group.label)
              if(this.groups.length>8){Text('图表展示前 8 组，导出汇总包含全部分组。').fontSize(11).fontColor($r('app.color.text_secondary'))}
              Button('导出图表 PNG').id('analytics-export-chart').width('100%').height(42).enabled(!this.busy).onClick(() => this.exportChart())
              Button('导出分组汇总 CSV').id('analytics-export-groups').width('100%').height(40).fontSize(13).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.export('csv',true))
            }.padding(18).width('100%').backgroundColor($r('app.color.surface')).borderRadius(20)
            Row({space:10}){Button('导出 CSV').id('analytics-export-csv').height(46).layoutWeight(1).backgroundColor($r('app.color.brand')).fontColor($r('app.color.inverse_text')).onClick(()=>this.export('csv'));Button('导出 JSON').id('analytics-export-json').height(46).layoutWeight(1).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.export('json'));}.width('100%')
            Button('沉淀分析报告到知萤笔记').id('analytics-share-lexinote').width('100%').height(46).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>this.shareReportToLexiNote())
            Button('保存分析项目').id('analytics-save-project').width('100%').height(46).backgroundColor($r('app.color.surface')).fontColor($r('app.color.brand')).onClick(()=>this.saveProject())
          }
          if(this.projects.length>0){
            Text('已保存的分析').fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary')).width('100%')
            ForEach(this.projects,(project:AnalysisProject)=>{Row({space:12}){Column({space:5}){Text(project.name).id('analytics-project-name-'+project.id).fontSize(14).fontColor($r('app.color.text_primary'));Text(new Date(project.savedAt).toLocaleDateString()).fontSize(11).fontColor($r('app.color.text_secondary'));}.alignItems(HorizontalAlign.Start).layoutWeight(1);Button('打开').id('analytics-project-open-'+project.id).height(34).fontSize(12).backgroundColor($r('app.color.brand_soft')).fontColor($r('app.color.brand')).onClick(()=>{this.input=project.csv;this.source=project.name;this.parse();});Button('×').id('analytics-project-delete-'+project.id).height(30).width(30).backgroundColor(Color.Transparent).fontColor($r('app.color.text_secondary')).onClick(()=>{this.projects=this.projects.filter((entry:AnalysisProject)=>entry.id!==project.id);StorageService.setValue('analytics-projects',JSON.stringify(this.projects));});}.id('analytics-project-row-'+project.id).padding(16).width('100%').backgroundColor($r('app.color.surface')).borderRadius(16)},(project:AnalysisProject)=>project.id)
          }
        }.width('100%').padding({left:22,right:22,top:12,bottom:44 + this.bottomInset})
      }.id('analytics-scroll').width('100%').height('100%').contentStartOffset(56)
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
      const param = context.pathInfo.param as AnalyticsRouteParam;
      if (param) {
        this.initialFilePath = param.filePath;
        this.loadInitial();
      }
    })
    .backgroundColor($r('app.color.background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
