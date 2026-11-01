import { uiMaterial } from '@kit.ArkUI';
import { LumiIcon } from './LumiIcon';

@Component
export struct LumiNavigation {
  @Prop active: number = 0;
  onSelect: (index: number) => void = () => {};
  @State private immersiveSupported: boolean = false;
  private readonly navMaterial: uiMaterial.ImmersiveMaterial = new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
    interactive: true,
    applyShadow: false,
    lightEffect: { color: $r('app.color.dock_light') }
  });

  aboutToAppear(): void {
    try { this.immersiveSupported = uiMaterial.isImmersiveMaterialSupported(); } catch {}
  }

  @Builder
  navigationItem(index: number, title: string, icon: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 9 }) {
        LumiIcon({ name: icon, iconSize: 21, muted: this.active !== index })
        Text(title).fontSize(15).fontWeight(this.active === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.active === index ? $r('app.color.brand') : $r('app.color.text_secondary'))
      }.padding({ left: 20, right: 20 })
    }.height(44).borderRadius(16)
      .backgroundColor(this.active === index ? $r('app.color.brand_soft') : Color.Transparent)
      .systemMaterial(this.immersiveSupported && this.active === index ? this.navMaterial : undefined)
      .accessibilityText(title).accessibilityDescription(this.active === index ? '已选中' : `前往${title}`)
      .onClick(() => { this.onSelect(index); })
  }

  build() {
    Row({ space: 8 }) {
      Row({ space: 10 }) {
        Image($r('app.media.lumi_logo')).width(34).height(34).borderRadius(10)
        Text('LumiKit').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
      }.margin({ right: 36 })
      this.navigationItem(0, '首页', 'home')
      this.navigationItem(1, '工具', 'tools')
      this.navigationItem(2, '记录', 'history')
      this.navigationItem(3, '我的', 'profile')
    }.height(60).width('auto')
  }
}
