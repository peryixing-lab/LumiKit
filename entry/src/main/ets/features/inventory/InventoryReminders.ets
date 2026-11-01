import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { calendarManager } from '@kit.CalendarKit';
import { InventoryCalendar } from './InventoryCalendar';
import { StorageService } from '../../core/StorageService';
import { InventoryItem, isValidDate } from './InventoryModels';

export class LumiReminderPlan {
  key: string = '';
  itemId: string = '';
  title: string = '';
  content: string = '';
  time: number = 0;
}
class LumiScheduledReminder {
  key: string = '';
  id: number = -1;
  signature: string = '';
  notificationId: number = 0;
}
export function inventoryReminderPlans(items: InventoryItem[], now: number): LumiReminderPlan[] {
  const plans: LumiReminderPlan[] = [];
  for (const item of items) {
    if (item.archived) { continue; }
    const dates: string[] = [item.warrantyReminderDate || ''];
    const keys: string[] = [item.id + '/warranty'];
    const titles: string[] = ['保修提醒'];
    const contents: string[] = [item.name + ' · 保修截止 ' + item.warrantyDate];
    for (const loan of item.lending) {
      if (!loan.returnedAt && loan.dueDate) {
        dates.push(loan.dueDate); keys.push(item.id + '/loan/' + loan.id); titles.push('借出到期提醒');
        contents.push(item.name + ' · 借给 ' + loan.borrower + '，预计今日归还');
      }
    }
    for (let i = 0; i < dates.length; i++) {
      if (!isValidDate(dates[i])) { continue; }
      const parts = dates[i].split('-').map((part: string) => Number(part));
      const time = new Date(parts[0], parts[1] - 1, parts[2], 9, 0).getTime();
      if (time <= now) { continue; }
      plans.push({ key: keys[i], itemId: item.id, title: titles[i], content: contents[i], time: time });
    }
  }
  return plans.sort((left: LumiReminderPlan, right: LumiReminderPlan) => left.time - right.time);
}
export class InventoryReminders {
  private static queue: Promise<void> = Promise.resolve();
  static async enable(ctx: common.UIAbilityContext, items: InventoryItem[]): Promise<void> {
    if (await StorageService.getSetting('inventoryReminderBackend', 'agent') === 'calendar') {
      await InventoryReminders.enableCalendar(ctx, items); return;
    }
    if (!await notificationManager.isNotificationEnabled()) { await notificationManager.requestEnableNotification(ctx); }
    await StorageService.setSetting('inventoryRemindersEnabled', 'true');
    await InventoryReminders.sync(items, ctx);
  }
  static async enableCalendar(ctx: common.UIAbilityContext, items: InventoryItem[]): Promise<void> {
    await InventoryCalendar.requestAccess(ctx);
    await StorageService.setSetting('inventoryReminderBackend', 'calendar');
    await StorageService.setSetting('inventoryRemindersEnabled', 'true');
    await InventoryReminders.sync(items, ctx);
  }
  static async sync(items: InventoryItem[], ctx?: common.Context): Promise<void> {
    const task = InventoryReminders.queue.then(async () => {
      if (await StorageService.getSetting('inventoryRemindersEnabled', 'false') !== 'true') { return; }
      const plans = inventoryReminderPlans(items, Date.now());
      const useCalendar = await StorageService.getSetting('inventoryReminderBackend', 'agent') === 'calendar';
      let scheduled = JSON.parse(await StorageService.getValue('inventory.reminders', '[]')) as LumiScheduledReminder[];
      // Persist every successful system change so partial failures can be retried safely.
      for (const previous of scheduled.slice()) {
        const plan = plans.find((entry: LumiReminderPlan) => entry.key === previous.key && JSON.stringify(entry) === previous.signature && previous.notificationId > 0);
        if (!plan || useCalendar) {
          try { await reminderAgentManager.cancelReminder(previous.id); } catch (error) { if ((error as BusinessError).code !== 1700003) { throw new Error((error as Error).message || '系统提醒更新失败'); } }
          scheduled = scheduled.filter((entry: LumiScheduledReminder) => entry.id !== previous.id);
          await StorageService.setValue('inventory.reminders', JSON.stringify(scheduled));
        }
      }
      if (useCalendar) {
        if (!ctx) { throw new Error('请打开物品详情更新日历提醒'); }
        const events: calendarManager.Event[] = plans.map((plan: LumiReminderPlan): calendarManager.Event => ({
          type: calendarManager.EventType.NORMAL, title: plan.title + ' · 集萤', description: plan.content,
          startTime: plan.time, endTime: plan.time + 5 * 60000, reminderTime: [0],
          identifier: 'com.lovexjy.LumiKit.inventory.' + plan.key
        }));
        await InventoryCalendar.sync(ctx, events); return;
      }
      for (const plan of plans) {
        if (scheduled.some((entry: LumiScheduledReminder) => entry.key === plan.key)) { continue; }
        const date = new Date(plan.time);
        let notificationId = 1000;
        while (scheduled.some((entry: LumiScheduledReminder) => entry.notificationId === notificationId)) { notificationId++; }
        const request: reminderAgentManager.ReminderRequestCalendar = {
          reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
          dateTime: { year: date.getFullYear(), month: date.getMonth() + 1, day: date.getDate(), hour: 9, minute: 0 },
          title: plan.title, content: plan.content, ringDuration: 0, notificationId: notificationId,
          wantAgent: { pkgName: 'com.lovexjy.LumiKit', abilityName: 'EntryAbility', parameters: { lumiItemId: plan.itemId } }
        };
        const id = await reminderAgentManager.publishReminder(request);
        scheduled.push({ key: plan.key, id: id, signature: JSON.stringify(plan), notificationId: notificationId });
        await StorageService.setValue('inventory.reminders', JSON.stringify(scheduled));
      }
    });
    InventoryReminders.queue = task.catch(() => {}); await task;
  }
}
