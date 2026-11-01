#!/usr/bin/env python3
"""Continue isolated acceptance from the notification permission sheet."""
import runpy,json
from pathlib import Path
scope=runpy.run_path(str(Path(__file__).with_name('emulator-next-release-check.py')),run_name='lumi_ui_helpers')
tap,find,back,cmd,check,text,shot=[scope[key] for key in ['tap','find','back','cmd','check','text','shot']]
results=scope['results'];OUT=scope['OUT'];args=scope['args']
results.extend(json.loads((OUT/'ui-checks.json').read_text()).get('passed',[]))
try:
 tap('允许',text=True,scroll=False);shot('notification-enabled');back();back()
 tap('nav-tab-3',scroll=False);tap('导出完整备份',text=True);shot('complete-backup-save-dialog')
 check('complete backup is generated with real workspace files before system export','.lumibak' in text())
 print('BACKUP_UI '+text(),flush=True)
except Exception as error:
 print('FAIL '+str(error),flush=True);shot('backup-ui-failure');raise
finally:
 (OUT/'ui-checks.json').write_text(json.dumps({'device':args.device,'passed':results},ensure_ascii=False,indent=2))
