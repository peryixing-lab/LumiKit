import { taskpool, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { testRegex } from './DeveloperUtils';

@Concurrent
function regexTask(pattern: string, flags: string, input: string): string {
  return testRegex(pattern, flags, input);
}

export class DeveloperRuntime {
  static async sha256(input: string): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    // The native TextEncoder returns undefined for an empty string, despite its declared return type.
    if (input.length > 0) {
      const bytes: Uint8Array = new util.TextEncoder().encodeInto(input);
      await digest.update({ data: bytes });
    }
    const result = await digest.digest();
    let output: string = '';
    for (let index: number = 0; index < result.data.length; index++) {
      output += result.data[index].toString(16).padStart(2, '0');
    }
    return output;
  }

  static uuids(count: number): string {
    if (!Number.isInteger(count) || count < 1 || count > 100) {
      throw new Error('生成数量应为 1–100 之间的整数。');
    }
    const values: string[] = [];
    for (let index: number = 0; index < count; index++) {
      values.push(util.generateRandomUUID(true));
    }
    return values.join('\n');
  }

  static async regex(pattern: string, flags: string, input: string): Promise<string> {
    const task: taskpool.Task = new taskpool.Task(regexTask, pattern, flags, input);
    // Isolate matching from the UI thread. A pathological expression is stopped
    // by the SDK task timeout instead of freezing the page.
    return await taskpool.execute(task, { timeout: 1500 }) as string;
  }
}
