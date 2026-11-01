import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

/** Entry point: aa test -b com.lovexjy.LumiKit -m entry_test -s unittest OpenHarmonyTestRunner */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {}

  onRun(): void {
    const testArgs = abilityDelegatorRegistry.getArguments();
    if (!testArgs.parameters['timeout']) { testArgs.parameters['timeout'] = '120000'; }
    Hypium.hypiumTest(abilityDelegatorRegistry.getAbilityDelegator(), testArgs, testsuite);
  }
}
