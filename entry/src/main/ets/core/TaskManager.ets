import { util } from '@kit.ArkTS';
import { StorageService } from './StorageService';

export type TaskState = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';

export class TaskRecord {
  id: string = '';
  toolId: string = '';
  title: string = '';
  state: TaskState = 'pending';
  progress: number = 0;
  inputPaths: string[] = [];
  outputPaths: string[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
  error: string = '';
}

/** Durable task metadata only. Passwords, conversion parameters, and input bodies never enter this store. */
export class TaskManager {
  private static writes: Promise<void> = Promise.resolve();
  private static progressAt: Map<string, number> = new Map<string, number>();

  private static validPaths(paths: string[]): boolean {
    return Array.isArray(paths) && paths.length <= 20000 && paths.every((path: string) =>
      typeof path === 'string' && path.length > 0 && path.length <= 4096 && !path.includes('\u0000'));
  }

  private static async read(): Promise<TaskRecord[]> {
    const raw = await StorageService.getValue('tasks', '[]');
    let records: TaskRecord[];
    try { records = JSON.parse(raw) as TaskRecord[]; }
    catch (_) { return []; }
    if (!Array.isArray(records)) { return []; }
    const states: string[] = ['pending', 'running', 'completed', 'failed', 'cancelled'];
    const seen = new Set<string>();
    return records.filter((record: TaskRecord) => {
      if (record === null || typeof record !== 'object' || typeof record.id !== 'string' || record.id.length === 0 || record.id.length > 200 || seen.has(record.id) ||
        typeof record.toolId !== 'string' || record.toolId.length > 100 || typeof record.title !== 'string' || record.title.length > 200 ||
        typeof record.state !== 'string' || !states.includes(record.state) || typeof record.progress !== 'number' || !Number.isFinite(record.progress) ||
        typeof record.createdAt !== 'number' || !Number.isFinite(record.createdAt) || record.createdAt < 0 ||
        typeof record.updatedAt !== 'number' || !Number.isFinite(record.updatedAt) || record.updatedAt < 0 ||
        typeof record.error !== 'string' || record.error.length > 1000 || !TaskManager.validPaths(record.inputPaths) || !TaskManager.validPaths(record.outputPaths)) { return false; }
      seen.add(record.id); return true;
    }).sort((a: TaskRecord, b: TaskRecord) => b.createdAt - a.createdAt).slice(0, 100).map((record: TaskRecord): TaskRecord => ({
      id: record.id, toolId: record.toolId, title: record.title, state: record.state,
      progress: Math.min(100, Math.max(0, record.progress)), inputPaths: record.inputPaths.slice(), outputPaths: record.outputPaths.slice(),
      createdAt: record.createdAt, updatedAt: record.updatedAt, error: record.error
    }));
  }

  private static async mutate(operation: (records: TaskRecord[]) => void): Promise<void> {
    const next = TaskManager.writes.then(async () => {
      const records = await TaskManager.read();
      operation(records);
      await StorageService.setValue('tasks', JSON.stringify(records.slice(0, 100)));
    });
    TaskManager.writes = next.catch(() => {});
    await next;
  }

  static async list(): Promise<TaskRecord[]> {
    await TaskManager.writes;
    return TaskManager.read();
  }

  static async begin(toolId: string, title: string, inputPaths: string[]): Promise<string> {
    if (!TaskManager.validPaths(inputPaths)) { throw new Error('任务输入文件列表无效'); }
    const record = new TaskRecord();
    record.id = util.generateRandomUUID(true);
    record.toolId = toolId.slice(0, 100);
    record.title = title.slice(0, 200);
    record.inputPaths = inputPaths.slice();
    record.createdAt = Date.now(); record.updatedAt = record.createdAt;
    await TaskManager.mutate((records: TaskRecord[]) => { records.unshift(record); });
    return record.id;
  }

  static async running(id: string): Promise<void> {
    await TaskManager.mutate((records: TaskRecord[]) => {
      const record = records.find((task: TaskRecord) => task.id === id);
      if (record && record.state === 'pending') { record.state = 'running'; record.updatedAt = Date.now(); }
    });
  }

  static async progress(id: string, value: number): Promise<void> {
    if (!Number.isFinite(value)) { return; }
    const now = Date.now(); const previous = TaskManager.progressAt.get(id) || 0;
    if (value < 100 && now - previous < 500) { return; }
    TaskManager.progressAt.set(id, now);
    await TaskManager.mutate((records: TaskRecord[]) => {
      const record = records.find((task: TaskRecord) => task.id === id);
      if (record && (record.state === 'running' || record.state === 'pending')) {
        record.progress = Math.max(record.progress, Math.min(100, Math.max(0, Math.round(value))));
        record.updatedAt = now;
      }
    });
  }

  static async complete(id: string, outputPaths: string[]): Promise<void> {
    if (!TaskManager.validPaths(outputPaths)) { throw new Error('任务输出文件列表无效'); }
    await TaskManager.mutate((records: TaskRecord[]) => {
      const record = records.find((task: TaskRecord) => task.id === id);
      if (record && (record.state === 'pending' || record.state === 'running')) {
        record.state = 'completed'; record.progress = 100; record.outputPaths = outputPaths.slice(); record.error = ''; record.updatedAt = Date.now();
      }
    });
    TaskManager.progressAt.delete(id);
  }

  static async fail(id: string, message: string, cancelled: boolean = false): Promise<void> {
    await TaskManager.mutate((records: TaskRecord[]) => {
      const record = records.find((task: TaskRecord) => task.id === id);
      if (record && (record.state === 'pending' || record.state === 'running')) {
        record.state = cancelled ? 'cancelled' : 'failed'; record.error = message.slice(0, 1000); record.updatedAt = Date.now();
      }
    });
    TaskManager.progressAt.delete(id);
  }

  static async recoverInterrupted(): Promise<void> {
    await TaskManager.mutate((records: TaskRecord[]) => {
      const now = Date.now();
      records.forEach((record: TaskRecord) => {
        if (record.state === 'pending' || record.state === 'running') {
          record.state = 'failed'; record.error = '应用上次退出时任务未完成，可重新选择参数后重试。'; record.updatedAt = now;
        }
      });
    });
    TaskManager.progressAt.clear();
  }
}
