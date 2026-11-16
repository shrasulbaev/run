"""Exercise the deployed demo using a new synthetic account; never print tokens."""
import argparse
import json
import secrets
from urllib.request import Request, urlopen
from urllib.error import HTTPError

parser = argparse.ArgumentParser()
parser.add_argument('api_url')
args = parser.parse_args()
base = args.api_url.rstrip('/')

def call(method, path, body=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    req = Request(base + path, method=method, headers=headers,
                  data=None if body is None else json.dumps(body).encode())
    try:
        response = urlopen(req, timeout=120)
    except HTTPError as error:
        response = error
    with response:
        data = response.read()
        return response.status, json.loads(data) if data else {}

status, health = call('GET', '/health')
assert status == 200 and health['status'] == 'ok'
email = f'deploy-check-{secrets.token_hex(6)}@example.com'
status, challenge = call('POST', '/auth/request-code', {'email': email})
assert status == 200
verify = {'challenge_id': challenge['challenge_id'], 'code': '11111', 'nickname': 'Deployment Check'}
assert call('POST', '/auth/verify', verify)[0] == 400
verify['code'] = '00000'
status, session = call('POST', '/auth/verify', verify)
assert status == 200 and session['user']['email'] == email
assert call('POST', '/auth/verify', verify)[0] == 400
status, profile = call('PATCH', '/me/goal', {'step_goal': 10000}, session['access_token'])
assert status == 200 and profile['step_goal'] == 10000
status, rotated = call('POST', '/auth/refresh', {'refresh_token': session['refresh_token']})
assert status == 200
assert call('POST', '/auth/refresh', {'refresh_token': session['refresh_token']})[0] == 401
assert call('GET', '/me', token=rotated['access_token'])[1]['step_goal'] == 10000
assert call('POST', '/auth/logout', {'refresh_token': rotated['refresh_token']}, rotated['access_token'])[0] == 204
assert call('GET', '/me', token=rotated['access_token'])[0] == 401
print('PASS: health, wrong OTP, registration, replay protection, saved goal, token rotation, logout.')
