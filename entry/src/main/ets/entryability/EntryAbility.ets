import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { StorageService } from '../core/StorageService';
import { FileService } from '../core/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KeyboardAvoidMode, window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined;
  private avoidListening: boolean = false;
  private readonly avoidListener: (options: window.AvoidAreaOptions) => void = (_options: window.AvoidAreaOptions): void => {
    this.updateInsets();
  };

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.receiveShare(_want);
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
  }

  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void { this.receiveShare(want); }

  private async receiveShare(want: Want): Promise<void> {
    if (want.action !== 'ohos.want.action.sendData' && want.action !== 'ohos.want.action.viewData') {
      const itemId = want.parameters?.['lumiItemId'];
      if (typeof itemId === 'string') { AppStorage.setOrCreate('lumiOpenItemId', itemId); }
      return;
    }
    try {
      await StorageService.init(this.context);
      const uris: string[] = [];
      if (want.action === 'ohos.want.action.sendData') {
        const data = await systemShare.getSharedData(want);
        for (const record of data.getRecords()) { if (record.uri) { uris.push(record.uri); } }
      } else if (want.uri) { uris.push(want.uri); }
      const files = await FileService.importUris(this.context, uris);
      AppStorage.setOrCreate('lumiIncomingPaths', JSON.stringify(files.map((file) => file.path)));
    } catch (error) { AppStorage.setOrCreate('lumiIncomingError', '分享文件导入失败：' + (error as Error).message); hilog.error(0x1040, 'LumiKit', 'Shared file import failed: %{public}s', (error as Error).message); }
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    this.mainWindow = stage.getMainWindowSync();
    stage.loadContent('pages/Index', (error) => {
      if (error.code) { hilog.error(0x1040, 'LumiKit', 'Unable to load main page, code %{public}d', error.code); }
      this.mainWindow?.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
      this.updateInsets();
      this.mainWindow?.on('avoidAreaChange', this.avoidListener);
      this.avoidListening = true;
      this.updateBars(this.context.config);
    });
  }

  onConfigurationUpdate(configuration: Configuration): void { this.updateBars(configuration); }

  private updateInsets(): void {
    if (!this.mainWindow) { return; }
    const system = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const indicator = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const bottom = Math.max(system.bottomRect.height, indicator.bottomRect.height);
    AppStorage.setOrCreate('lumiBottomInset', this.mainWindow.getUIContext().px2vp(bottom));
  }

  private updateBars(configuration: Configuration): void {
    if (!this.mainWindow) { return; }
    const dark = configuration.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const background = dark ? '#111A29' : '#F3F7FD';
    const foreground = dark ? '#EDF3FF' : '#1D2D43';
    try {
      this.mainWindow.setWindowBackgroundColor(background);
    } catch (error) {
      hilog.warn(0x1040, 'LumiKit', 'Window background unavailable');
    }
    this.mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000', navigationBarColor: '#00000000',
      statusBarContentColor: foreground, navigationBarContentColor: foreground
    }).catch(() => { hilog.warn(0x1040, 'LumiKit', 'System bar appearance unavailable'); });
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow && this.avoidListening) { this.mainWindow.off('avoidAreaChange', this.avoidListener); }
    this.avoidListening = false;
    this.mainWindow = undefined;
  }
}
