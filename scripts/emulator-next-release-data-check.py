#!/usr/bin/env python3
"""Continue acceptance after saving the chart in the system picker."""
import runpy,json
from pathlib import Path
scope=runpy.run_path(str(Path(__file__).with_name('emulator-next-release-check.py')),run_name='lumi_ui_helpers')
tap,find,top,back,cmd,check,text,shot,open_tool,dismiss_keyboard=[scope[key] for key in ['tap','find','top','back','cmd','check','text','shot','open_tool','dismiss_keyboard']]
results=scope['results'];OUT=scope['OUT'];args=scope['args']
results.extend(json.loads((OUT/'ui-checks.json').read_text()).get('passed',[]))
try:
 if args.phase != 'data':
  top();check('chart is exported through the real system save picker','1200 × 900 图表已导出' in text());shot('chart-export-success');back()
  open_tool('json');tap('填入示例',text=True);tap('dev-draft-toggle');back();open_tool('json')
 top();check('developer input draft restores after reopening','"name":"LumiKit"' in text());shot('developer-draft');back()
 open_tool('inventory');tap('inventory-create');tap('inventory-input-物品名称 *');cmd('ui','text','验收相机');dismiss_keyboard()
 tap('inventory-input-保修提醒日期');cmd('ui','text','2030-01-10');dismiss_keyboard();tap('inventory-save')
 tap('inventory-enable-reminders');shot('notification-request')
 print('NOTIFICATION_UI '+text(),flush=True)
except Exception as error:
 print('FAIL '+str(error),flush=True);shot('data-ui-failure');raise
finally:
 (OUT/'ui-checks.json').write_text(json.dumps({'device':args.device,'passed':results},ensure_ascii=False,indent=2))
