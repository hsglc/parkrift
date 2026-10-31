"""Prints where the app stands in App Store Connect: each version's state, the review
submissions with their dates and items, and the attached build. Read-only.
Run by .github/workflows/asc-status.yml. Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID
"""
import os, time, json
import jwt, requests

API = 'https://api.appstoreconnect.apple.com'


def token():
    key = open(os.environ['ASC_KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'},
                      key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def get(path):
    r = requests.get(API + path, headers={'Authorization': 'Bearer ' + token()}, timeout=60)
    if r.status_code >= 400:
        print(f'::warning::GET {path} -> {r.status_code}: {r.text[:300]}')
        return {'data': []}
    return r.json()


def note(text):
    print(text)
    print(f'::notice::{text}')


def main():
    apps = get(f"/v1/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")['data']
    if not apps:
        note('App not found')
        return
    app_id = apps[0]['id']
    for v in get(f'/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=5')['data']:
        a = v['attributes']
        build = get(f"/v1/appStoreVersions/{v['id']}/build").get('data') or {}
        number = (build.get('attributes') or {}).get('version', '-')
        note(f"Version {a.get('versionString')}: state={a.get('appStoreState')} / {a.get('appVersionState')} "
             f"created={a.get('createdDate')} build={number}")
    subs = get(f'/v1/reviewSubmissions?filter[app]={app_id}&limit=10')['data']
    for s in subs:
        a = s['attributes']
        items = get(f"/v1/reviewSubmissions/{s['id']}/items")['data']
        states = ', '.join(i['attributes'].get('state', '?') for i in items) or 'no items'
        note(f"Review submission: state={a.get('state')} submitted={a.get('submittedDate')} items=[{states}]")
    if not subs:
        note('No review submissions')


main()
