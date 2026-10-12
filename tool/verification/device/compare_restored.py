from pathlib import Path
import json,collections
out=Path('docs/development/v1.0.1/device-diagnostics')
def report(file):
 s=(out/file).read_text(encoding='utf-8-sig');line=next(l for l in s.splitlines() if l.startswith('INSTRUMENTATION_RESULT: storageBaseline='))
 return json.loads(line.split('=',1)[1])
b=json.loads((out/'Qinghe_V101_pretest_20261007.json').read_text(encoding='utf-8'))
a=report('after-restore.txt')
before=report('before-upgrade.txt')
keys=['weekday','startSection','endSection','startWeek','endWeek','pattern','room','startMinute','endMinute','timeSource']
def row(v):return tuple(None if x is None else str(x) for x in v)
expected=collections.Counter(row([c['id']]+[s.get(k) for k in keys]) for c in b['courses'] for s in c['sessions'])
actual=collections.Counter(row(r) for r in a['sessionContent'])
assert actual==expected,{'missing':list((expected-actual).items()),'extra':list((actual-expected).items())}
for table in ['course_rows','semester_rows']:
 old=next(r for r in before['tableDigests'] if r['name']==table);new=next(r for r in a['tableDigests'] if r['name']==table)
 assert old==new,(table,old,new)
save=report('after-test-save.txt')
result={'actualSaveCourseCount':next(r['rows'] for r in save['tableDigests'] if r['name']=='course_rows'),'restoredCourseCount':len(b['courses']),'restoredSessionFieldCount':sum(expected.values()),'allSessionFieldsMatchBackup':True,'courseAndSemesterRowsMatchBeforeUpgrade':True,'restoredTermWeeks':17,'ocrDirectoryBytes':a['ocrDirectoryBytes'],'appBytes':a.get('systemAppBytes'),'dataBytes':a.get('systemDataBytes'),'cacheBytes':a.get('systemCacheBytes')}
(out/'restore-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(result,ensure_ascii=False))