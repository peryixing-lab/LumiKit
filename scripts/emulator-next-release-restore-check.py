#!/usr/bin/env python3
"""Continue isolated acceptance from the complete-backup save sheet."""
import runpy,json
from pathlib import Path
scope=runpy.run_path(str(Path(__file__).with_name('emulator-next-release-check.py')),run_name='lumi_ui_helpers')
tap,cmd,text,shot=[scope[key] for key in ['tap','cmd','text','shot']]
cmd('ui','click','1130','260')
tap('恢复备份',text=True)
shot('complete-backup-select-dialog')
print(text(),flush=True)
