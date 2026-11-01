#!/usr/bin/env python3
"""Finish isolated acceptance from the inspected backup confirmation dialog."""
import runpy,json
from pathlib import Path
s=runpy.run_path(str(Path(__file__).with_name('emulator-next-release-check.py')),run_name='helpers')
results=s['results'];OUT=s['OUT'];args=s['args'];results.extend(json.loads((OUT/'ui-checks.json').read_text()).get('passed',[]))
try:
 s['tap']('恢复',text=True,scroll=False);s['find']('恢复完成',text=True)
 s['check']('complete backup is selected, validated and restored through real system pickers',True);s['shot']('complete-backup-restored')
 s['enter_search']('验收相机');s['tap']('物品 · 验收相机',text=True)
 node=s['find']('inventory-detail-name');s['check']('global search opens the exact inventory record',node.get('text')=='验收相机');s['shot']('global-search-item')
 s['back']();s['back']();s['tap']('nav-tab-0',scroll=False);s['shot']('home')
except Exception as error:
 print('FAIL '+str(error),flush=True);s['shot']('finish-ui-failure');raise
finally:
 (OUT/'ui-checks.json').write_text(json.dumps({'device':args.device,'passed':results},ensure_ascii=False,indent=2))
