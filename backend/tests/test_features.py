import base64
import io
import uuid
from datetime import timedelta
from PIL import Image
from sqlalchemy import select
from test_auth import client, login, challenge
from app.main import now
from app.storage import Activity, Attempt, User
from app.routes import SAMPLES


def auth(client, identifier='runner@example.com', phone=False):
    c=client.post('/auth/request-code',json={'identifier':identifier,'channel':'phone' if phone else 'email'})
    assert c.status_code==200,c.text
    r=client.post('/auth/verify',json={'challenge_id':c.json()['challenge_id'],'code':'00000','nickname':'Runner'})
    assert r.status_code==200,r.text
    return r.json(),{'Authorization':'Bearer '+r.json()['access_token']}


def trace(route):
    stamp=int((now()-timedelta(hours=3)).timestamp()*1000)
    return [dict(lat=lat,lon=lon,accuracy=5,time_ms=stamp+i*10000,mocked=False) for i,(lat,lon) in enumerate(SAMPLES[route])]


def finish_body(route='park-sprint'):
    fixes=trace(route);ms=fixes[-1]['time_ms']-fixes[0]['time_ms']
    return dict(id=str(uuid.uuid4()),route_id=route,elapsed_ms=ms,moving_ms=ms,trace=fixes)


def test_phone_normalized_and_profile_private(client):
    data,h=auth(client,'+996 (700) 123-456',True)
    assert data['user']['phone']=='+996700123456'
    assert data['user']['email'] is None
    again,_=auth(client,'+996700123456',True)
    assert again['user']['id']==data['user']['id']
    edited=client.patch('/me/profile',headers=h,json={'nickname':'  Shera  ','city':'Бишкек','bio':'Приватная заметка'})
    assert edited.json()['nickname']=='Shera'
    other,h2=auth(client,'other@example.com')
    public=client.get('/users/'+data['user']['id'],headers=h2).json()
    assert set(public)=={'id','nickname','avatar_version','achievements','completed_routes'}
    assert public['nickname']=='Shera'
    assert client.post('/auth/request-code',json={'phone':'700123456'}).status_code==422


def test_avatar_sanitized_persistent_and_deletable(client):
    data,h=auth(client)
    raw=io.BytesIO();Image.new('RGB',(900,600),'orange').save(raw,format='PNG')
    result=client.post('/me/photo',headers=h,json={'image_base64':base64.b64encode(raw.getvalue()).decode()})
    assert result.status_code==200,result.text
    photo=client.get('/users/'+data['user']['id']+'/photo',headers=h)
    im=Image.open(io.BytesIO(photo.content))
    assert im.format=='JPEG' and im.size==(512,512) and not im.getexif()
    assert client.get('/users/'+data['user']['id']+'/photo').status_code==401
    assert client.post('/me/photo',headers=h,json={'image_base64':'bm90IGltYWdl'}).status_code==422
    assert client.post('/me/photo',headers=h,json={'image_base64':None}).status_code==200
    assert client.get('/users/'+data['user']['id']+'/photo',headers=h).status_code==404


def test_verified_result_idempotent_and_attempt_single_use(client):
    data,h=auth(client)
    body=finish_body()
    ticket=client.post('/attempts',headers=h,json={'route_id':body['route_id']}).json()['id']
    body['attempt_id']=ticket
    # Only the test fixture moves the server's clock; the API accepts no start timestamp.
    with client.app.state.sessions() as db:
        db.get(Attempt,ticket).started_at=now()-timedelta(milliseconds=body['elapsed_ms'])
        db.commit()
    result=client.post('/activities',headers=h,json=body)
    assert result.status_code==200,result.text
    assert result.json()['ranked']
    assert client.post('/activities',headers=h,json=body).json()==result.json()
    body['id']=str(uuid.uuid4())
    assert client.post('/activities',headers=h,json=body).status_code==409
    history=client.get('/me/activity',headers=h).json()
    assert history['total']==1 and history['distance_m']==1233
    ranking=client.get('/rankings/park-sprint',headers=h).json()
    assert ranking['me']['rank']==1 and ranking['participants']==1


def test_shortcut_mock_and_unconfirmed_time_rejected(client):
    _,h=auth(client)
    body=finish_body()
    body['trace']=body['trace'][::10]
    assert client.post('/activities',headers=h,json=body).status_code==422
    body=finish_body();body['trace'][5]['mocked']=True
    assert client.post('/activities',headers=h,json=body).status_code==422
    body=finish_body();body['trace'][5]['accuracy']=100
    assert client.post('/activities',headers=h,json=body).status_code==422
    body=finish_body();body['attempt_id']=client.post('/attempts',headers=h,json={'route_id':body['route_id']}).json()['id']
    assert client.post('/activities',headers=h,json=body).status_code==422


def test_offline_result_in_history_but_not_speed_ranking(client):
    _,h=auth(client)
    result=client.post('/activities',headers=h,json=finish_body('city-bird'))
    assert result.status_code==200,result.text
    assert result.json()['ranked'] is False
    assert client.get('/me/activity',headers=h).json()['drawings']==1
    assert client.get('/rankings/city-bird',headers=h).json()['participants']==0


def test_walk_daily_cap_ties_month_and_best_race(client):
    data,h=auth(client); other,h2=auth(client,'second@example.com')
    stamp=now().replace(day=10,hour=12)
    # Calendar fixture ensures current month, with multiple completions on one day.
    with client.app.state.sessions() as db:
        for uid,day,route,elapsed in [(data['user']['id'],0,'city-bird',60000),(data['user']['id'],0,'city-bird',60000),(other['user']['id'],0,'city-bird',60000),(data['user']['id'],0,'park-sprint',600000),(data['user']['id'],0,'park-sprint',500000),(other['user']['id'],0,'park-sprint',500000)]:
            db.add(Activity(id=str(uuid.uuid4()),user_id=uid,route_id=route,started_at=stamp-timedelta(seconds=1000),completed_at=stamp+timedelta(days=day),elapsed_ms=elapsed,moving_ms=elapsed,distance_m=1233,ranked=True,evidence_hash='x'*64,sample_count=100))
        db.commit()
    walk=client.get('/rankings/city-bird',headers=h).json()
    assert [e['score'] for e in walk['entries']]==[1,1]
    assert [e['rank'] for e in walk['entries']]==[1,1]
    run=client.get('/rankings/park-sprint',headers=h).json()
    assert [e['score'] for e in run['entries']]==[500000,500000]
    assert [e['rank'] for e in run['entries']]==[1,1]
    assert client.get('/rankings/park-sprint?period=invalid',headers=h).status_code==422
