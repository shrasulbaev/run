"""Hosted v1.1 smoke; creates demo-only accounts, no leaderboard results."""
import base64
import io
import json
import sys
import uuid
from urllib.request import Request,urlopen
from PIL import Image

base=sys.argv[1].rstrip('/')

def call(method,path,body=None,token=None):
    headers={'Content-Type':'application/json'}
    if token:headers['Authorization']='Bearer '+token
    req=Request(base+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method)
    with urlopen(req,timeout=120) as r:
        raw=r.read()
        return json.loads(raw) if raw and 'json' in r.headers.get('Content-Type','') else raw

def login(identifier,channel):
    challenge=call('POST','/auth/request-code',{'identifier':identifier,'channel':channel})
    return call('POST','/auth/verify',{'challenge_id':challenge['challenge_id'],'code':'00000','nickname':'QA smoke'})

uid=uuid.uuid4().hex[:12]
email=login(f'qa-{uid}@example.com','email')
phone=login('+999'+str(int(uid,16))[-10:],'phone')
t=email['access_token']
assert phone['user']['phone'] and phone['user']['email'] is None
assert call('PATCH','/me/goal',{'step_goal':12000},t)['step_goal']==12000
assert call('GET','/me',token=t)['step_goal']==12000
assert call('PATCH','/me/profile',{'nickname':'QA '+uid[:6],'city':'Бишкек','bio':'Private QA note'},t)['bio']=='Private QA note'
raw=io.BytesIO();Image.new('RGB',(48,48),'#ff7a20').save(raw,format='PNG')
assert call('POST','/me/photo',{'image_base64':base64.b64encode(raw.getvalue()).decode()},t)['avatar_version']
photo=call('GET','/users/'+email['user']['id']+'/photo',token=phone['access_token'])
assert Image.open(io.BytesIO(photo)).size==(512,512)
public=call('GET','/users/'+email['user']['id'],token=phone['access_token'])
assert set(public)=={'id','nickname','avatar_version','achievements','completed_routes'}
assert call('GET','/me/activity',token=t)['total']==0
for route in ['city-bird','park-sprint']:
    result=call('GET','/rankings/'+route,token=t)
    assert isinstance(result['entries'],list) and result['me'] is None
call('POST','/me/photo',{'image_base64':None},t)
for session in [email,phone]:call('POST','/auth/logout',{'refresh_token':session['refresh_token']},session['access_token'])
print('PASS: phone/email OTP, persistent goal, profile, sanitized photo, privacy, history, both rankings, logout. No ranking results inserted.')
