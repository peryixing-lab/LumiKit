import { uiMaterial } from '@kit.ArkUI';
import { LumiIcon } from './LumiIcon';

/** Shared custom title inside the native Navigation title bar. */
@Component
export struct LumiBackHeader {
  @Prop title: ResourceStr = '';
  @Prop showTutorial: boolean = false;
  @Prop tutorialEnabled: boolean = true;
  onBack: () => void = () => {};
  onTutorial: () => void = () => {};
  @State private immersiveSupported: boolean = false;
  private readonly backMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: true,
    applyShadow: true,
    lightEffect: { color: $r('app.color.dock_light') }
  });

  aboutToAppear(): void {
    try { this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported(); } catch {}
  }

  build() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        LumiIcon({ name: 'back', iconSize: 23 })
      }.id('secondary-back').width(40).height(40).padding(0)
        .systemMaterial(this.immersiveSupported ? this.backMaterial : undefined)
        .accessibilityText('返回').onClick(() => { this.onBack(); })
      Text(this.title).fontSize(20).fontWeight(FontWeight.Bold).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.text_primary')).layoutWeight(1)
      if (this.showTutorial) {
        Button('使用教程', { type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL })
          .id('tool-tutorial').height(44).constraintSize({ minWidth: 80 }).fontSize(12)
          .fontWeight(FontWeight.Medium).fontColor($r('app.color.brand'))
          .backgroundColor(this.immersiveSupported ? Color.Transparent : $r('app.color.brand_soft')).borderRadius(14)
          .systemMaterial(this.immersiveSupported ? this.backMaterial : undefined)
          .padding({ left: 12, right: 12 })
          .enabled(this.tutorialEnabled)
          .accessibilityText('查看当前工具使用教程').onClick(() => { this.onTutorial(); })
      }
    }.id('secondary-title').width('100%').height('100%').padding({ left: 16, right: 22 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
