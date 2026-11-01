import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { calendarManager } from '@kit.CalendarKit';

const CALENDAR_ACCOUNT: string = 'com.lovexjy.LumiKit.reminders';
const EVENT_PREFIX: string = 'com.lovexjy.LumiKit.inventory.';

/** Only manages events created by LumiKit in its dedicated local calendar. */
export class InventoryCalendar {
  static async requestAccess(ctx: common.UIAbilityContext): Promise<void> {
    const permissions: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
    const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(ctx, permissions);
    if (result.authResults.length !== permissions.length || result.authResults.some((status: number) => status !== 0)) {
      throw new Error('日历权限未开启，可在系统设置中允许后重试');
    }
  }

  static async sync(ctx: common.Context, desired: calendarManager.Event[],
    accountName: string = CALENDAR_ACCOUNT): Promise<void> {
    const manager = calendarManager.getCalendarManager(ctx);
    const calendars = await manager.getAllCalendars();
    let calendar = calendars.find((entry: calendarManager.Calendar) => entry.getAccount().name === accountName &&
      entry.getAccount().type === calendarManager.CalendarType.LOCAL);
    if (!calendar) {
      if (desired.length === 0) { return; }
      calendar = await manager.createCalendar({ name: accountName, type: calendarManager.CalendarType.LOCAL,
        displayName: '集萤到期提醒' });
      await calendar.setConfig({ enableReminder: true });
    }
    const existing = await calendar.getEvents();
    const retained: string[] = [];
    for (const event of existing) {
      if (!event.identifier?.startsWith(EVENT_PREFIX) || event.id === undefined) { continue; }
      const next = desired.find((entry: calendarManager.Event) => entry.identifier === event.identifier);
      if (!next || retained.includes(event.identifier)) { await calendar.deleteEvent(event.id); continue; }
      retained.push(event.identifier);
      if (next.startTime !== event.startTime || next.endTime !== event.endTime || next.title !== event.title ||
        next.description !== event.description || JSON.stringify(next.reminderTime) !== JSON.stringify(event.reminderTime)) {
        const updated: calendarManager.Event = { id: event.id, type: next.type, title: next.title,
          description: next.description, startTime: next.startTime, endTime: next.endTime,
          reminderTime: next.reminderTime, identifier: next.identifier };
        await calendar.updateEvent(updated);
      }
    }
    for (const next of desired) {
      if (next.identifier?.startsWith(EVENT_PREFIX) && !retained.includes(next.identifier)) {
        await calendar.addEvent(next); retained.push(next.identifier);
      }
    }
  }
}
