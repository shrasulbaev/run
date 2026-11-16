from datetime import timedelta
import pytest
from fastapi.testclient import TestClient
from app.main import Challenge, Settings, create_app, now


@pytest.fixture
def client(tmp_path):
    app = create_app(Settings(app_env='test', database_url=f'sqlite:///{tmp_path}/test.db'))
    with TestClient(app) as c:
        yield c


def challenge(client, email='runner@example.com'):
    result = client.post('/auth/request-code', json={'email': email})
    assert result.status_code == 200
    return result.json()['challenge_id']


def login(client):
    result = client.post('/auth/verify', json={'challenge_id': challenge(client), 'code': '00000', 'nickname': 'Адам'})
    assert result.status_code == 200
    return result.json()


def test_registration_login_goal_and_logout(client):
    data = login(client)
    headers = {'Authorization': 'Bearer ' + data['access_token']}
    assert client.get('/me', headers=headers).json()['nickname'] == 'Адам'
    assert client.patch('/me/goal', headers=headers, json={'step_goal': 10000}).json()['step_goal'] == 10000
    again = client.post('/auth/verify', json={'challenge_id': challenge(client), 'code': '00000'}).json()
    assert again['user']['id'] == data['user']['id']
    assert again['user']['step_goal'] == 10000
    assert client.post('/auth/logout', headers=headers, json={'refresh_token': data['refresh_token']}).status_code == 204
    assert client.get('/me', headers=headers).status_code == 401


def test_wrong_expired_and_replayed_codes(client):
    cid = challenge(client)
    for _ in range(5):
        assert client.post('/auth/verify', json={'challenge_id': cid, 'code': '12345'}).status_code == 400
    assert client.post('/auth/verify', json={'challenge_id': cid, 'code': '00000', 'nickname': 'Test'}).status_code == 400
    cid = challenge(client)
    with client.app.state.sessions() as db:
        db.get(Challenge, cid).expires_at = now() - timedelta(seconds=1)
        db.commit()
    assert client.post('/auth/verify', json={'challenge_id': cid, 'code': '00000'}).status_code == 400
    cid = challenge(client)
    body = {'challenge_id': cid, 'code': '00000', 'nickname': 'Test'}
    assert client.post('/auth/verify', json=body).status_code == 200
    assert client.post('/auth/verify', json=body).status_code == 400


def test_rotating_refresh_and_bad_input(client):
    data = login(client)
    body = {'refresh_token': data['refresh_token']}
    assert client.post('/auth/refresh', json=body).status_code == 200
    assert client.post('/auth/refresh', json=body).status_code == 401
    assert client.get('/me').status_code == 401
    assert client.post('/auth/request-code', json={'email': 'bad'}).status_code == 422
    assert client.patch('/me/goal', headers={'Authorization': 'Bearer ' + data['access_token']}, json={'step_goal': 0}).status_code == 422


def test_resend_invalidates_old_code_and_rate_limits(client):
    old = challenge(client)
    challenge(client)
    assert client.post('/auth/verify', json={'challenge_id': old, 'code': '00000'}).status_code == 400
    for _ in range(3):
        challenge(client)
    assert client.post('/auth/request-code', json={'email': 'runner@example.com'}).status_code == 429


def test_fixed_code_cannot_start_in_production():
    with pytest.raises(RuntimeError, match='forbidden'):
        create_app(Settings(app_env='production', test_auth_enabled=True))


def test_hosted_demo_requires_secret_and_persistent_database():
    with pytest.raises(RuntimeError, match='JWT_SECRET'):
        Settings(app_env='demo').runtime_database_url()
    with pytest.raises(RuntimeError, match='PostgreSQL'):
        Settings(app_env='demo', jwt_secret='s' * 48).runtime_database_url()
    url = Settings(app_env='demo', jwt_secret='s' * 48,
                   database_url='postgresql://runner:password@host/adam?channel_binding=require').runtime_database_url()
    assert url.drivername == 'postgresql+psycopg'
    assert url.query['sslmode'] == 'require'
    assert url.query['channel_binding'] == 'require'


def test_health_checks_database_and_identifies_demo_status(client):
    health = client.get('/health')
    assert health.status_code == 200
    assert health.json() == {'status': 'ok', 'test_auth': True, 'environment': 'test'}
