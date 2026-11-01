import { curves } from '@kit.ArkUI';
import { LumiBackHeader } from '../../components/LumiBackHeader';
import { HELP_ARTICLES, HELP_SECTIONS, LumiHelpArticle, LumiHelpSection } from './HelpContent';
import { LumiHelpRouteParam } from './HelpNavigation';

@Builder
export function helpBuilder() {
  HelpPage()
}

@Component
export struct HelpPage {
  @State private helpQuery: string = '';
  @State private selectedSection: string = 'all';
  @State private expandedSections: string[] = ['getting-started'];
  @State private expandedArticles: string[] = ['home'];
  @State private focusedArticleId: string = '';
  @StorageProp('lumiBottomInset') private bottomInset: number = 0;
  private pathStack: NavPathStack = new NavPathStack();
  private readonly pageScroller: Scroller = new Scroller();

  private openArticle(articleId: string): void {
    const article: LumiHelpArticle | undefined = HELP_ARTICLES.find((item: LumiHelpArticle): boolean =>
      item.id === articleId);
    if (article !== undefined) {
      this.focusedArticleId = article.id;
      this.expandedArticles = [article.id];
    }
  }

  private focusedArticles(): LumiHelpArticle[] {
    return HELP_ARTICLES.filter((article: LumiHelpArticle): boolean => article.id === this.focusedArticleId);
  }

  private relatedArticles(): LumiHelpArticle[] {
    const focused: LumiHelpArticle | undefined = HELP_ARTICLES.find((article: LumiHelpArticle): boolean =>
      article.id === this.focusedArticleId);
    if (focused === undefined) {
      return [];
    }
    return HELP_ARTICLES.filter((article: LumiHelpArticle): boolean =>
      article.sectionId === focused.sectionId && article.id !== focused.id);
  }

  private showAllInstructions(): void {
    this.focusedArticleId = '';
    this.selectedSection = 'all';
    this.helpQuery = '';
    this.expandedSections = ['getting-started'];
    this.expandedArticles = ['home'];
    this.pageScroller.scrollEdge(Edge.Top);
  }

  private articlesFor(sectionId: string): LumiHelpArticle[] {
    return HELP_ARTICLES.filter((article: LumiHelpArticle): boolean =>
      article.sectionId === sectionId && article.matches(this.helpQuery));
  }

  private visibleSections(): LumiHelpSection[] {
    return HELP_SECTIONS.filter((section: LumiHelpSection): boolean =>
      (this.selectedSection === 'all' || section.id === this.selectedSection) && this.articlesFor(section.id).length > 0);
  }

  private resultCount(): number {
    return HELP_ARTICLES.filter((article: LumiHelpArticle): boolean =>
      (this.selectedSection === 'all' || article.sectionId === this.selectedSection) && article.matches(this.helpQuery)).length;
  }

  private searchChanged(text: string): void {
    this.helpQuery = text;
    if (text.trim().length > 0) {
      this.expandedSections = this.visibleSections().map((section: LumiHelpSection): string => section.id);
      this.expandedArticles = HELP_ARTICLES.filter((article: LumiHelpArticle): boolean => article.matches(text))
        .map((article: LumiHelpArticle): string => article.id);
    } else {
      this.expandedSections = this.selectedSection === 'all' ? ['getting-started'] : [this.selectedSection];
      this.expandedArticles = [];
    }
  }

  private selectSection(sectionId: string): void {
    this.selectedSection = sectionId;
    this.expandedSections = sectionId === 'all' ? ['getting-started'] : [sectionId];
    this.expandedArticles = [];
    if (this.helpQuery.trim().length > 0) {
      this.searchChanged(this.helpQuery);
    }
  }

  private toggleSection(sectionId: string): void {
    this.expandedSections = this.expandedSections.includes(sectionId) ?
      this.expandedSections.filter((id: string): boolean => id !== sectionId) : this.expandedSections.concat([sectionId]);
  }

  private toggleArticle(articleId: string): void {
    this.expandedArticles = this.expandedArticles.includes(articleId) ?
      this.expandedArticles.filter((id: string): boolean => id !== articleId) : this.expandedArticles.concat([articleId]);
  }

  private expandAll(): void {
    this.expandedSections = this.visibleSections().map((section: LumiHelpSection): string => section.id);
    this.expandedArticles = HELP_ARTICLES.filter((article: LumiHelpArticle): boolean =>
      (this.selectedSection === 'all' || article.sectionId === this.selectedSection) && article.matches(this.helpQuery))
      .map((article: LumiHelpArticle): string => article.id);
  }

  private collapseAll(): void {
    this.expandedSections = [];
    this.expandedArticles = [];
  }

  @Builder
  private categoryChip(sectionId: string, label: string) {
    Button(label, { type: ButtonType.Normal })
      .height(38)
      .padding({ left: 15, right: 15 })
      .borderRadius(12)
      .fontSize(13)
      .fontColor(this.selectedSection === sectionId ? $r('app.color.inverse_text') : $r('app.color.text_secondary'))
      .backgroundColor(this.selectedSection === sectionId ? $r('app.color.brand') : $r('app.color.surface'))
      .onClick(() => { this.selectSection(sectionId); })
  }

  @Builder
  private articleDetails(article: LumiHelpArticle) {
    Column({ space: 14 }) {
      ForEach(article.steps, (instruction: string, instructionIndex: number) => {
        Row({ space: 10 }) {
          Text((instructionIndex + 1).toString().padStart(2, '0'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
            .width(25)
            .margin({ top: 4 })
          Text(instruction)
            .fontSize(14)
            .lineHeight(24)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (instruction: string): string => article.id + ':step:' + instruction)
      if (article.notes.length > 0) {
        Column({ space: 8 }) {
          Text('使用边界')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          ForEach(article.notes, (note: string) => {
            Text('· ' + note)
              .fontSize(12)
              .lineHeight(21)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }, (note: string): string => article.id + ':note:' + note)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(14)
        .backgroundColor($r('app.color.soft_surface'))
        .borderRadius(12)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, bottom: 20 })
  }

  @Builder
  private articleCard(article: LumiHelpArticle) {
    Column() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text(article.title)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(article.summary)
              .fontSize(12)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(this.expandedArticles.includes(article.id) ? '−' : '+')
            .fontSize(23)
            .fontColor($r('app.color.brand'))
            .width(24)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .id('help-article-' + article.id)
      .width('100%')
      .constraintSize({ minHeight: 76 })
      .padding(18)
      .backgroundColor(Color.Transparent)
      .borderRadius(16)
      .accessibilityText(article.title + (this.expandedArticles.includes(article.id) ? '，收起说明' : '，展开说明'))
      .onClick(() => { this.toggleArticle(article.id); })
      if (this.expandedArticles.includes(article.id)) {
        this.articleDetails(article)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface'))
    .borderRadius(18)
  }

  @Builder
  private sectionCard(section: LumiHelpSection) {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text(section.title)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text(section.caption + ' · ' + this.articlesFor(section.id).length.toString() + ' 条')
              .fontSize(12)
              .lineHeight(19)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(this.expandedSections.includes(section.id) ? '⌃' : '⌄')
            .fontSize(22)
            .fontColor($r('app.color.text_secondary'))
            .width(24)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
      }
      .id('help-section-' + section.id)
      .width('100%')
      .constraintSize({ minHeight: 70 })
      .padding({ left: 3, right: 3, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(Color.Transparent)
      .accessibilityText(section.title + (this.expandedSections.includes(section.id) ? '，收起分类' : '，展开分类'))
      .onClick(() => { this.toggleSection(section.id); })
      if (this.expandedSections.includes(section.id)) {
        ForEach(this.articlesFor(section.id), (article: LumiHelpArticle) => {
          this.articleCard(article)
        }, (article: LumiHelpArticle): string => article.id)
      }
    }
    .width('100%')
  }

  @Builder
  private pageTitleBar() {
    LumiBackHeader({ title: this.focusedArticleId.length > 0 ? '使用教程' : '使用说明',
      onBack: () => { this.pathStack.pop(); } })
  }

  @Builder
  private focusedInstructions() {
    Column({ space: 18 }) {
      Row({ space: 8 }) {
        Text('当前工具教程')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Button('查看全部说明', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('help-view-all')
          .height(40)
          .fontSize(13)
          .fontColor($r('app.color.brand'))
          .onClick(() => { this.showAllInstructions(); })
      }
      .width('100%')
      ForEach(this.focusedArticles(), (article: LumiHelpArticle) => {
        this.articleCard(article)
      }, (article: LumiHelpArticle): string => article.id)
      if (this.relatedArticles().length > 0) {
        Text('相关教程')
          .id('help-related-title')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ top: 8 })
        ForEach(this.relatedArticles(), (article: LumiHelpArticle) => {
          this.articleCard(article)
        }, (article: LumiHelpArticle): string => article.id)
      }
    }
    .id('help-focused-content')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
        Column({ space: 18 }) {
          if (this.focusedArticleId.length > 0) {
            Column() { this.focusedInstructions() }.width('100%').transition(this.modeTransition())
          } else {
            Column({ space: 18 }) {
              Column({ space: 8 }) {
                Text('让每个工具，都顺手。')
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text('从首页到每一项处理，查步骤，也了解当前版本的使用边界。')
                  .fontSize(13)
                  .lineHeight(22)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              Search({ value: this.helpQuery, placeholder: '搜索工具、操作或使用限制' })
                .id('help-search')
                .width('100%')
                .height(52)
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_secondary'))
                .backgroundColor($r('app.color.surface'))
                .onChange((text: string) => { this.searchChanged(text); })
              Scroll() {
                Row({ space: 8 }) {
                  this.categoryChip('all', '全部主题')
                  ForEach(HELP_SECTIONS, (section: LumiHelpSection) => {
                    this.categoryChip(section.id, section.title)
                  }, (section: LumiHelpSection): string => section.id)
                }
              }
              .width('100%')
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              Row({ space: 8 }) {
                Text(this.resultCount().toString() + ' 条说明')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)
                Button('展开全部', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .fontSize(12)
                  .height(36)
                  .fontColor($r('app.color.brand'))
                  .enabled(this.resultCount() > 0)
                  .onClick(() => { this.expandAll(); })
                Button('收起', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .fontSize(12)
                  .height(36)
                  .fontColor($r('app.color.text_secondary'))
                  .onClick(() => { this.collapseAll(); })
              }
              .width('100%')
              if (this.resultCount() === 0) {
                Column({ space: 10 }) {
                  Text('暂时没有找到相关说明')
                    .fontSize(17)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  Text('试试「导出」「保修」「JSON」等关键词，\n或切换到全部主题。')
                    .fontSize(13)
                    .lineHeight(23)
                    .textAlign(TextAlign.Center)
                    .fontColor($r('app.color.text_secondary'))
                  Button('查看全部说明', { buttonStyle: ButtonStyleMode.TEXTUAL })
                    .fontSize(13)
                    .fontColor($r('app.color.brand'))
                    .onClick(() => { this.selectedSection = 'all'; this.searchChanged(''); })
                }
                .width('100%')
                .padding({ top: 32, bottom: 36 })
              } else {
                ForEach(this.visibleSections(), (section: LumiHelpSection) => {
                  this.sectionCard(section)
                }, (section: LumiHelpSection): string => section.id)
              }
            }.width('100%').transition(this.modeTransition())
          }
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 12, bottom: 36 + this.bottomInset })
      }
      .width('100%')
      .height('100%')
      .contentStartOffset(56)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .hideBackButton(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .title({ builder: () => { this.pageTitleBar(); }, height: 56 }, {
      barStyle: BarStyle.STACK,
      scrollEffectOptions: { scrollEffectType: ScrollEffectType.GRADUAL_BLUR }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param: LumiHelpRouteParam = context.pathInfo.param as LumiHelpRouteParam;
      if (param && typeof param.articleId === 'string') {
        this.openArticle(param.articleId);
      }
    })
    .backgroundColor($r('app.color.background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
