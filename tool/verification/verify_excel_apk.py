from pathlib import Path
import hashlib,json,zipfile,sys
apk=Path(sys.argv[1]);out=Path(sys.argv[2]) if len(sys.argv)>2 else Path('docs/development/v1.0.1/apk-verification.json')
with zipfile.ZipFile(apk) as z:
 names=z.namelist();libs=sorted(n for n in names if n.startswith('lib/'))
 banned=[n for n in names if n.startswith('assets/ocr/') or n.startswith('assets/flutter_assets/assets/ocr/') or n.endswith(('.onnx','.ort','.tflite')) or ('lib/' in n and any(s in n.lower() for s in ['onnx','mlkit']))]
 assert not banned,banned
 assert libs and all(n.startswith('lib/arm64-v8a/') for n in libs)
 assert 'lib/arm64-v8a/libapp.so' in libs and 'lib/arm64-v8a/libflutter.so' in libs
 template='assets/flutter_assets/assets/templates/qinghe_timetable_template.xlsx'
 assert hashlib.sha256(z.read(template)).digest()==hashlib.sha256(Path('assets/templates/qinghe_timetable_template.xlsx').read_bytes()).digest()
 soundhash={hashlib.sha256(z.read(n)).hexdigest() for n in names if n.endswith('.wav')}
 sounds=list(Path('android/app/src/main/res/raw').glob('qinghe_*.wav'));assert len(sounds)==7
 assert all(hashlib.sha256(p.read_bytes()).hexdigest() in soundhash for p in sounds)
 for name in names:
  if name.endswith('.dex'):
   dex=z.read(name)
   for token in [b'ai/onnxruntime/',b'com/google/mlkit/',b'io/flutter/plugins/imagepicker/',b'com/yalantis/ucrop/']:
    assert token not in dex,(name,token)
 result={'apk':str(apk),'bytes':apk.stat().st_size,'MiB':round(apk.stat().st_size/1048576,2),'MB':round(apk.stat().st_size/1e6,2),'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'modelAssetCount':0,'recognitionNativeLibraryCount':0,'recognitionDexClassesPresent':False,'nativeLibraries':libs,'excelTemplateHashMatches':True,'builtInRingtonesValidated':len(sounds)}
out.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(result,ensure_ascii=False))