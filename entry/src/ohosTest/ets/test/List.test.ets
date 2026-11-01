import nextReleaseNativeTest from './NextReleaseNative.test';
import platformNativeTest from './PlatformNative.test';

export default function testsuite(): void {
  platformNativeTest();
  nextReleaseNativeTest();
}
