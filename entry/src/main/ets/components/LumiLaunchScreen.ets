/** The launch screen follows real initialization steps; it never adds waiting time. */
@Component
export struct LumiLaunchScreen {
  @Prop startupStep: number = 0;
  @Prop errorMessage: string = '';
  @Prop reduceMotion: boolean = false;
  @Prop bottomInset: number = 0;
  @State launchWidth: number = 390;
  @State launchHeight: number = 760;
  onRetry: () => void = () => {};

  private compact(): boolean { return this.launchHeight < 620; }
  private brandSize(): number {
    const preferred = this.compact() ? Math.max(104, this.launchHeight * 0.32) : 276;
    return Math.min(preferred, Math.max(80, this.launchWidth - 48));
  }
  private contentMinHeight(): number {
    const footerHeight = this.compact() ? 34 : 70;
    return Math.max(0, this.launchHeight - (this.compact() ? 16 : 24) - footerHeight - this.bottomInset);
  }

  private stepLabel(): string {
    if (this.startupStep === 1) { return '正在恢复上次记录'; }
    if (this.startupStep === 2) { return '正在整理文件工作区'; }
    return '正在打开本地数据';
  }

  @Builder
  brandMark() {
    Stack() {
      Column().width(this.brandSize() * 268 / 276).height(this.brandSize() * 268 / 276).borderRadius(this.brandSize() / 2)
        .border({ width: 1, color: $r('app.color.divider') }).opacity(0.6)
      Column().width(this.brandSize() * 224 / 276).height(this.brandSize() * 224 / 276).borderRadius(this.brandSize() / 2)
        .backgroundColor($r('app.color.brand_soft')).opacity(0.32)
      Column().width(this.brandSize() * 178 / 276).height(this.brandSize() * 178 / 276).borderRadius(this.brandSize() / 2)
        .backgroundColor($r('app.color.brand_soft')).opacity(0.48)
      Image($r('app.media.lumi_logo')).width(this.brandSize() * 132 / 276).height(this.brandSize() * 132 / 276)
        .borderRadius(this.brandSize() * 32 / 276)
        .objectFit(ImageFit.Contain).accessibilityLevel('no')
    }.width(this.brandSize()).height(this.brandSize()).accessibilityLevel('no')
  }

  @Builder
  progressStep(index: number) {
    Column().width(this.startupStep === index ? 24 : 12).height(4).borderRadius(2)
      .backgroundColor(index <= this.startupStep ? $r('app.color.brand') : $r('app.color.divider'))
      .animation({ duration: this.reduceMotion ? 0 : 160, curve: Curve.EaseOut })
      .accessibilityLevel('no')
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          this.brandMark()
          Text('集萤 LumiKit').fontSize(this.compact() ? 26 : 30).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary')).letterSpacing(0.2).margin({ top: 2 })
          Text('让繁杂，变简单。').fontSize(this.compact() ? 14 : 16).fontColor($r('app.color.text_secondary'))
            .margin({ top: this.compact() ? 8 : 12 })
          Column({ space: this.compact() ? 12 : 16 }) {
            if (this.errorMessage.length > 0) {
              Text('工具台暂时未能打开').fontSize(14).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary')).textAlign(TextAlign.Center)
              Text(this.errorMessage).fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).constraintSize({ maxWidth: 288 })
              Button('重新打开', { type: ButtonType.Capsule }).height(44).padding({ left: 28, right: 28 })
                .fontSize(14).fontWeight(FontWeight.Medium).backgroundColor($r('app.color.brand'))
                .fontColor($r('app.color.inverse_text')).onClick(() => { this.onRetry(); })
            } else {
              Row({ space: 6 }) {
                this.progressStep(0)
                this.progressStep(1)
                this.progressStep(2)
              }.height(4).accessibilityLevel('no')
              Text(this.stepLabel()).fontSize(12).fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center).accessibilityText(this.stepLabel())
            }
          }.margin({ top: this.compact() ? 22 : 38 }).constraintSize({ minHeight: this.compact() ? 58 : 84 })
        }.width('100%').constraintSize({ minHeight: this.contentMinHeight(), maxWidth: 560 })
          .justifyContent(FlexAlign.Center)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      Column({ space: 8 }) {
        Text('本地优先 · 即开即用').fontSize(12).fontWeight(FontWeight.Medium)
          .lineHeight(18)
          .fontColor($r('app.color.brand_ink')).letterSpacing(1)
        if (!this.compact()) {
          Text('文件、灵感和生活，都在这里井然有序。').fontSize(11).lineHeight(18)
            .fontColor($r('app.color.text_secondary')).textAlign(TextAlign.Center)
        }
      }.padding({ bottom: (this.compact() ? 16 : 26) + this.bottomInset })
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: this.compact() ? 16 : 24 })
      .backgroundColor($r('app.color.background'))
      .onAreaChange((_old: Area, current: Area) => {
        this.launchWidth = Number(current.width);
        this.launchHeight = Number(current.height);
      })
  }
}
