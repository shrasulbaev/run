"""Small licensed OpenFreeMap extract. <=3000 tiles / 50 MB, <=4 requests."""
import concurrent.futures
import gzip
import hashlib
import json
import math
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'mobile/assets/maps/offline'
BBOX = [74.42,42.77,74.80,42.97]
UA = 'ADAM-RUN/1.1 (offline Bishkek; https://github.com/shrasulbaev/run)'

def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':UA}), timeout=45) as r:
        return r.read()

def xy(lon,lat,z):
    return int((lon+180)/360*(1<<z)), int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*(1<<z))

def main():
    metadata = json.loads(get('https://tiles.openfreemap.org/planet'))
    existing=ROOT/'mobile/assets/maps/offline_manifest.json'
    previous=json.loads(existing.read_text()) if existing.exists() else {}
    template = previous.get('source',metadata['tiles'][0])
    jobs=[]
    for z in range(8,15):
        x0,y1=xy(BBOX[0],BBOX[1],z); x1,y0=xy(BBOX[2],BBOX[3],z)
        jobs += [(z,x,y) for x in range(x0,x1+1) for y in range(y0,y1+1)]
    assert len(jobs)<3000
    print(f'Downloading {len(jobs)} tiles', flush=True)
    def fetch(job):
        z,x,y=job; path=OUT/f'{z}/{x}/{y}.pbf'
        if path.exists(): return path, path.read_bytes(),0
        raw=get(template.format(z=z,x=x,y=y)); size=len(raw)
        if raw[:2]==b'\x1f\x8b': raw=gzip.decompress(raw)
        path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(raw)
        return path,raw,size
    entries=[]; total=0
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for path,raw,size in pool.map(fetch,jobs):
            total+=size
            if total>49_000_000: raise RuntimeError('Download limit reached')
            entries.append({'path':str(path.relative_to(ROOT/'mobile')), 'sha256':hashlib.sha256(raw).hexdigest()})
    for block in ['0-255','256-511','1024-1279','8192-8447']:
        path=OUT/f'fonts/Noto Sans Regular/{block}.pbf'; path.parent.mkdir(parents=True,exist_ok=True)
        raw=get(f'https://tiles.openfreemap.org/fonts/Noto%20Sans%20Regular/{block}.pbf')
        if raw[:2]==b'\x1f\x8b': raw=gzip.decompress(raw)
        path.write_bytes(raw); entries.append({'path':str(path.relative_to(ROOT/'mobile')),'sha256':hashlib.sha256(raw).hexdigest()})
    manifest={'version':'bishkek-20261117-v1','bounds':BBOX,'minzoom':8,'maxzoom':14,'tile_count':len(jobs),'download_bytes':previous.get('download_bytes',total),'source':template,'attribution':metadata['attribution'],'files':entries}
    (ROOT/'mobile/assets/maps/offline_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False))
    pub=ROOT/'mobile/pubspec.yaml'; s='\n'.join(line for line in pub.read_text().split('\n') if not line.startswith('    - assets/maps/offline/'));  s=s.replace('    - assets/maps/\n','    - assets/maps/\n'+''.join(f'    - {d}/\n' for d in sorted({str((ROOT/'mobile'/e['path']).parent.relative_to(ROOT/'mobile')) for e in entries})))
    pub.write_text(s)
    print(f'Done: {len(jobs)} tiles, {total/1e6:.1f} MB transferred',flush=True)

if __name__=='__main__': main()
