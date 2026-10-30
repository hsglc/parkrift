"""Adds a person as an internal TestFlight tester of the app through the App Store Connect API.
Run by .github/workflows/asc-tester.yml.

Internal testers must be App Store Connect users: the first run sends them an invitation
(Developer role, this app only, no certificates); once they accept it, a run adds them to the
app's internal TestFlight group, after which every build reaches them without review.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, EMAIL, FIRST_NAME, LAST_NAME
"""
import os, sys, time, json
import jwt, requests

API = 'https://api.appstoreconnect.apple.com/v1'


def token():
    key = open(os.environ['ASC_KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'},
                      key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, path, body=None, quiet=False):
    r = requests.request(method, API + path, headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'},
                         data=json.dumps(body) if body else None, timeout=60)
    if r.status_code >= 400:
        if not quiet:
            print(f'::warning::{method} {path} -> {r.status_code}: {r.text[:800]}')
        return None
    return r.json() if r.text else {}


def main():
    email = os.environ['EMAIL'].strip().lower()
    first, last = os.environ.get('FIRST_NAME') or 'Tester', os.environ.get('LAST_NAME') or 'Parkrift'
    apps = call('GET', f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")
    if not apps or not apps['data']:
        print('::error::App not found'); sys.exit(1)
    app = apps['data'][0]['id']

    users = call('GET', f'/users?filter[username]={email}') or {'data': []}
    if not users['data']:
        pending = call('GET', f'/userInvitations?filter[email]={email}') or {'data': []}
        if pending['data']:
            print(f'::notice::Invitation already sent to {email}; it has to be accepted (email from App Store Connect), then run this again.')
            return
        body = {'data': {'type': 'userInvitations',
                         'attributes': {'email': email, 'firstName': first, 'lastName': last, 'roles': ['DEVELOPER'],
                                        'allAppsVisible': False, 'provisioningAllowed': False},
                         'relationships': {'visibleApps': {'data': [{'type': 'apps', 'id': app}]}}}}
        if call('POST', '/userInvitations', body) is None:
            sys.exit(1)
        print(f'::notice::Invitation sent to {email} (Developer role, Parkrift only). After it is accepted, run this again to add them to TestFlight.')
        return

    groups = call('GET', f'/apps/{app}/betaGroups?limit=50') or {'data': []}
    internal = [g for g in groups['data'] if g['attributes'].get('isInternalGroup')]
    if not internal:
        made = call('POST', '/betaGroups', {'data': {'type': 'betaGroups', 'attributes': {'name': 'Ekip', 'isInternalGroup': True,
                                                                                            'hasAccessToAllBuilds': True},
                                                    'relationships': {'app': {'data': {'type': 'apps', 'id': app}}}}})
        if not made:
            sys.exit(1)
        internal = [made['data']]
    group = internal[0]
    print('Internal group:', group['attributes'].get('name'), group['id'])

    testers = call('GET', f'/betaTesters?filter[email]={email}') or {'data': []}
    if testers['data']:
        tester = testers['data'][0]['id']
        call('POST', f"/betaGroups/{group['id']}/relationships/betaTesters", {'data': [{'type': 'betaTesters', 'id': tester}]})
    else:
        made = call('POST', '/betaTesters', {'data': {'type': 'betaTesters',
                                                      'attributes': {'email': email, 'firstName': first, 'lastName': last},
                                                      'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': group['id']}]}}}})
        if not made:
            sys.exit(1)
    print(f'::notice::{email} is in the internal TestFlight group: the TestFlight invitation email follows.')


if __name__ == '__main__':
    main()
