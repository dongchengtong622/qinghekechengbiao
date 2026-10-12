from pathlib import Path
import subprocess,time,re,xml.etree.ElementTree as ET,json,sys
ADB='C:/Users/DCT13/AppData/Local/Temp/qh09t/android-sdk/platform-tools/adb.exe'
SERIAL='15495091960017A'
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'docs/development/v1.0.1/device-diagnostics'
REMOTE='/sdcard/Download/qinghe-v101-verification-ui.xml'
def adb(*args):
 r=subprocess.run([ADB,'-s',SERIAL,*map(str,args)],capture_output=True,encoding='utf-8',errors='replace',timeout=60)
 if r.returncode:raise RuntimeError(r.stdout+r.stderr)
 return r.stdout

def dump(name='current'):
 OUT.mkdir(parents=True,exist_ok=True)
 for attempt in range(3):
  try:
   adb('shell','uiautomator','dump',REMOTE);break
  except RuntimeError:
   if attempt==2:raise
   time.sleep(2)
 p=OUT/(name+'.xml');adb('pull',REMOTE,str(p.relative_to(ROOT)))
 nodes=list(ET.parse(p).iter('node'))
 return nodes

def labels(nodes):return '\n'.join((n.get('text') or n.get('content-desc') or '') for n in nodes)
def click(nodes,label,contains=False):
 targets=[n for n in nodes if any((label in v if contains else label==v) for v in (n.get('text',''),n.get('content-desc','')))]
 if not targets:raise RuntimeError('Cannot find '+label+'\n'+labels(nodes))
 targets=[n for n in targets if n.get('clickable')=='true'] or targets
 n=targets[-1];x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));adb('shell','input','tap',x2-50 if label=='单节时长' else (x1+x2)//2,y2-35 if label=='单节时长' else (y1+y2)//2);time.sleep(.7)
def back():adb('shell','input','keyevent',4);time.sleep(.6)
def text(value):adb('shell','input','text',value);time.sleep(.5)
if __name__=='__main__':
 if len(sys.argv)>1:click(dump(),sys.argv[1])
 ns=dump(sys.argv[2] if len(sys.argv)>2 else 'current')
 for n in ns:
  if n.get('text') or n.get('content-desc'):print(n.get('text'),n.get('content-desc'),n.get('bounds'))

