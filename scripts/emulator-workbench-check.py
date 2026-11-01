#!/usr/bin/env python3
"""Validate new workbench on the dedicated emulator using visible controls; never reset app data."""
import json, subprocess, time, argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NODE='/Users/thousandmiles/.nvm/versions/node/v22.23.2/bin/node'
CLI='/Users/thousandmiles/.nvm/versions/node/v22.23.2/lib/node_modules/@deveco/deveco-code/node_modules/@deveco/deveco-cli/cli.js'
HDC='/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc'
a=argparse.ArgumentParser();a.add_argument('--device',default='127.0.0.1:5557');a.add_argument('--phase',choices=['resume','finish','library','inventory','screenshots','organize','screenshots-finish','draft','draft-finish','resume-draft','thumbnails','image-compress','image-target','image-target-unmet','image-batch','image-batch-finish','pdf-compress','final-smoke','ocr-error'],default='resume');args=a.parse_args()
OUT=ROOT/'docs/validation/three-rounds';OUT.mkdir(parents=True,exist_ok=True)
reportpath=OUT/'ui-checks.json';checks=json.loads(reportpath.read_text()) if reportpath.exists() else []
def cmd(*parts):
 p=subprocess.run([NODE,CLI,*parts,'--device',args.device],cwd=ROOT,capture_output=True,text=True,timeout=45)
 if p.returncode:raise RuntimeError((p.stdout+p.stderr)[-1800:])
 (OUT/'last-command.log').write_text(' '.join(parts)+'\n'+p.stdout+p.stderr)
 return p.stdout
def flat(n):
 if isinstance(n,list):return [a for x in n for a in flat(x)]
 return [n]+[a for x in n.get('children',[]) for a in flat(x)]
def nodes():return flat(json.loads(cmd('ui','layout','--format','json')))
def visible(n):return 340<(n['bounds'][1]+n['bounds'][3])/2<2450
def find(text=None,id=None,scroll=True):
 for _ in range(8 if scroll else 1):
  n=next((n for n in nodes() if (n.get('text')==text if text is not None else n.get('id')==id) and (visible(n) or id in ['secondary-back','nav-tab-0','nav-tab-1','nav-tab-2','nav-tab-3'])),None)
  if n:return n
  cmd('ui','swipe','1100','2250','1100','700','--speed','2300')
 raise RuntimeError('Missing visible control: '+str(text or id))
def tapnode(n):
 b=n['bounds'];cmd('ui','click',str((b[0]+b[2])//2),str((b[1]+b[3])//2));time.sleep(.2)
def tap(text=None,id=None,scroll=True):tapnode(find(text,id,scroll))
def text():return '\n'.join(n.get('text','') for n in nodes())
def check(label,condition):
 if not condition:raise AssertionError(label+'\n'+text())
 checks.append(label);print('PASS '+label,flush=True);reportpath.write_text(json.dumps(checks,ensure_ascii=False,indent=2))
def shot(name):
 target=OUT/(name+'.png')
 if target.exists():target.unlink()
 cmd('ui','screenshot','--path',str(target))
def input_id(id,content):
 tap(id=id);subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent 2072 2017'],check=True,capture_output=True)
 cmd('ui','text',content)
 subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent Back'],check=True,capture_output=True)
def top():
 for _ in range(3):cmd('ui','swipe','1100','700','1100','2250','--speed','2500')
try:
 if args.phase=='resume':
  check('Native image conversion reaches page organizer','02 整理页面' in text())
  tap(text='旋转');shot('01-organize-rotated');tap(id='secondary-back',scroll=False)
  subprocess.run([HDC,'-t',args.device,'shell','aa force-stop com.lovexjy.LumiKit'],check=True,capture_output=True)
  cmd('run','--skip-build');time.sleep(1)
  top();resume=next((n for n in nodes() if n.get('id','').startswith('resume-flow-')),None)
  if not resume:
   cmd('ui','swipe','1100','2250','1100','1100','--speed','2300');resume=next(n for n in nodes() if n.get('id','').startswith('resume-flow-'))
  tapnode(resume);time.sleep(.5);check('Flow survives force-stop and resumes organizer','02 整理页面' in text());shot('02-resumed-organizer')
  tap(id='flow-next');time.sleep(.5);check('Native PDF organizer produces the next stage','03 文件大小' in text());shot('03-size-check')
 elif args.phase=='finish':
  input_id('flow-target','0');tap(id='flow-next');check('Invalid size cannot advance workflow','目标大小请输入' in text())
  top();input_id('flow-target','5');tap(id='flow-next');time.sleep(.5)
  check('Valid workflow produces a named final artifact','04 核对与分享' in text() and '提交材料.pdf' in text());shot('04-final-result')
  check('Final artifact shows provenance and a final-result label','最终成果' in text() and '来源' in text())
  tap(text='分享');time.sleep(.3);shot('05-share-panel');print('SHARE_PANEL '+text(),flush=True)
 elif args.phase=='organize':
  subprocess.run([HDC,'-t',args.device,'shell','uitest uiInput keyEvent Back'],check=True,capture_output=True)
  input_id('flow-recipe-name','QA每周材料');tap(id='flow-save-recipe');check('Workflow recipe saved for reuse','流程已保存到首页' in text())
  top();tap(text='整理');input_id('result-rename','QA-集萤-材料');input_id('result-tags','验收,材料');input_id('result-collection','QA资料集合');tap(text='保存整理');time.sleep(.4)
  top();check('Result rename and collection are persisted','QA-集萤-材料.pdf' in text() and 'QA资料集合' in text());shot('06-renamed-result')
  tap(text='移入回收站');tap(text='保存并返回首页');top();tap(text='导入文件');input_id('workspace-search','QA-集萤-材料');tap(id='workspace-trash')
  check('Trashed result is discoverable in recycle bin','QA-集萤-材料.pdf' in text() and '永久删除' in text());shot('07-trash')
  tap(text='恢复');tap(id='workspace-trash');check('Restored result keeps tags, collection and provenance','QA-集萤-材料.pdf' in text() and '#验收' in text() and '来源' in text());shot('08-restored')
  tap(id='secondary-back',scroll=False)
 elif args.phase=='inventory':
  top();tap(text='登记一件物品');check('New item starts with a short form', '补充购买、保修与其他信息' in text() and '购买价格 / 元' not in text());shot('11-item-short-form')
  input_id('inventory-input-物品名称 *','QA三轮验收相机');tap(id='inventory-save')
  check('An item can be saved with only a name','QA三轮验收相机' in text() and '编辑' in text());shot('12-item-saved');print(text(),flush=True)
 elif args.phase=='library':
  tap(text='导入文件');check('Workspace provides collection search and trash entry','回收站' in text());shot('06-library');print(text(),flush=True)
 elif args.phase=='screenshots':
  tap(id='home-screenshots');check('Screenshots workflow is reachable','截图整理成 PDF' in text());tap(text='从工作区选择');print(text(),flush=True)
 elif args.phase=='ocr-error':
  check('OCR service failure is visible and preserves the existing item name','系统文字识别服务超时' in text() and 'QA三轮验收相机' in text());shot('13-ocr-service-feedback')
  tap(id='secondary-back',scroll=False);tap(id='secondary-back',scroll=False);tap(id='secondary-back',scroll=False)
 elif args.phase=='draft':
  top();tap(text='导入文件');input_id('workspace-search','截图合集.pdf');tap(text='继续处理');tap(text='整理页面');time.sleep(.4)
  tap(id='pdf-load-pages');tap(text='旋转');input_id('file-result-name','QA页面续接');shot('14-pdf-draft-thumbnails')
  tap(id='secondary-back',scroll=False);tap(id='secondary-back',scroll=False)
  subprocess.run([HDC,'-t',args.device,'shell','aa force-stop com.lovexjy.LumiKit'],check=True,capture_output=True);cmd('run','--skip-build');top();tap(text='继续 PDF 页面整理 · 1 个文件')
  check('PDF tool restores the selected file and output name after restart','截图合集.pdf' in text() and 'QA页面续接' in text());shot('15-restored-pdf-draft');print(text(),flush=True)
 elif args.phase=='draft-finish':
  top()
  tap(id='pdf-load-pages');tap(text='旋转');input_id('file-result-name','QA页面续接');shot('14-pdf-draft-thumbnails')
  tap(id='secondary-back',scroll=False);tap(id='secondary-back',scroll=False)
  subprocess.run([HDC,'-t',args.device,'shell','aa force-stop com.lovexjy.LumiKit'],check=True,capture_output=True);cmd('run','--skip-build');top();tap(text='继续 PDF 页面整理 · 1 个文件')
  check('PDF tool restores the selected file and output name after restart','截图合集.pdf' in text() and 'QA页面续接' in text());shot('15-restored-pdf-draft');print(text(),flush=True)
 elif args.phase=='resume-draft':
  top();tap(text='继续 PDF 页面整理 · 1 个文件');check('PDF tool restores selected files after restart','截图合集.pdf' in text());find(id='file-result-name');check('PDF tool restores output naming after restart','QA页面续接' in text());shot('15-restored-pdf-draft')
  top();tap(text='预览第一份 PDF');time.sleep(.5);shot('16-pdf-native-preview');print(text(),flush=True)
 elif args.phase=='thumbnails':
  top();tap(text='继续 PDF 页面整理 · 1 个文件');find(text='第 1 位 · 原第 1 页');shot('17-thumbnails-fixed');tap(id='secondary-back',scroll=False)
 elif args.phase=='image-compress':
  top();tap(text='导入文件');input_id('workspace-search','学院数据示例_图表.png');tap(text='继续处理');tap(text='压缩图片');input_id('image-compress-target','0');tap(text='开始处理')
  check('Image compression rejects invalid targets','目标大小请输入' in text());top();input_id('image-compress-target','0.03');tap(text='开始处理');time.sleep(.5)
  check('Native image compression reports size savings','已压缩 1 张' in text() and '减少' in text());shot('18-image-compressed')
  tap(text='预览');time.sleep(.5);cmd('ui','swipe','1100','2250','1100','1100','--speed','1800');shot('19-image-compressed-preview');print(text(),flush=True)
 elif args.phase=='image-target':
  top();tap(text='导入文件');input_id('workspace-search','学院数据示例_图表.png');tap(text='继续处理');tap(text='压缩图片');input_id('image-compress-target','0.03')
  check('Fractional image targets retain the decimal point',find(id='image-compress-target')['text']=='0.03');tap(text='开始处理');time.sleep(.5)
  check('Fractional target produces a smaller image','已压缩 1 张' in text() and '尚未达到目标' not in text());shot('20-image-target-result');print(text(),flush=True)
 elif args.phase=='image-target-unmet':
  top();input_id('image-compress-target','0.001');check('Tiny targets retain the requested number',find(id='image-compress-target')['text']=='0.001');tap(text='开始处理');time.sleep(.5)
  check('Unreachable image targets are explicitly reported','尚未达到目标大小' in text());shot('21-image-target-unmet');print(text(),flush=True)
 elif args.phase=='image-batch':
  top();input_id('image-compress-target','0.03');tap(text='JPEG · 小巧通用');tap(text='WebP · 保留透明');top();tap(text='从工作区选择')
  images=[n for n in nodes() if n.get('text')=='学院数据示例_图表.png'];tapnode(images[-1]);tap(text='开始处理');time.sleep(.5)
  check('Native WebP batch compression reports two images','已压缩 2 张' in text());shot('22-image-batch-webp');print(text(),flush=True)
  tap(id='secondary-back',scroll=False);tap(id='secondary-back',scroll=False)
 elif args.phase=='image-batch-finish':
  top();tap(text='从工作区选择');tap(text='学院数据示例_图表_1.jpg');tap(text='开始处理');time.sleep(.5)
  check('Native WebP batch compression reports two images','已压缩 2 张' in text());shot('22-image-batch-webp');print(text(),flush=True)
  tap(id='secondary-back',scroll=False);tap(id='secondary-back',scroll=False)
 elif args.phase=='pdf-compress':
  top();tap(text='导入文件');input_id('workspace-search','截图合集.pdf');tap(text='继续处理');tap(text='压缩 PDF');input_id('pdf-target-mb','0.05')
  check('PDF targets retain decimal values',find(id='pdf-target-mb')['text']=='0.05');tap(text='开始处理');time.sleep(.5);check('Native PDF compression reduces the file','压缩前' in text() and '压缩后' in text());tap(text='预览');cmd('ui','swipe','1100','2250','1100','900','--speed','1800');shot('23-pdf-compression-preview');print(text(),flush=True)
 elif args.phase=='final-smoke':
  top();shot('24-home-final');tap(id='nav-tab-1');input_id('tool-search','图片压缩');check('Image compression is discoverable from tool search',find(id='tool-image-compress') is not None);shot('25-image-compression-entry');tap(id='tool-image-compress')
  check('Image compression opens with the new target controls',find(id='image-compress-target') is not None);shot('26-image-compression-settings');tap(id='secondary-back',scroll=False);tap(id='nav-tab-0');top()
 elif args.phase=='screenshots-finish':
  choices=[n for n in nodes() if n.get('text')=='学院数据示例_图表.png'];tapnode(choices[0]);tap(text='从工作区选择');choices=[n for n in nodes() if n.get('text')=='学院数据示例_图表.png'];tapnode(choices[-1])
  tap(id='flow-next');time.sleep(.5);check('Two images produce two editable PDF pages','第 2 页' in text());shot('09-screenshots-pages')
  tap(id='flow-next');tap(id='flow-next');check('Screenshots pipeline creates a two-page final PDF','截图合集.pdf' in text() and '2 页' in text());shot('10-screenshots-final')
  tap(text='保存并返回首页')
except Exception:
 shot('failure-'+args.phase);raise
