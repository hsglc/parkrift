"""Sets the App Store Connect app name, subtitle and privacy policy URL (every existing
localization) through the App Store Connect API. Run by .github/workflows/asc-app-info.yml.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, APP_NAME, SUBTITLE_EN, SUBTITLE_TR, PRIVACY_URL
"""
import os, sys, time, json
import jwt, requests

API = 'https://api.appstoreconnect.apple.com/v1'


def token():
    key = open(os.environ['ASC_KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'},
                      key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, path, body=None):
    r = requests.request(method, API + path, headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'},
                         data=json.dumps(body) if body else None, timeout=60)
    if r.status_code >= 400:
        print(f'::warning::{method} {path} -> {r.status_code}: {r.text[:600]}')
        return None
    return r.json() if r.text else {}


def main():
    apps = call('GET', f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")
    if not apps or not apps['data']:
        print('::error::App not found'); sys.exit(1)
    app = apps['data'][0]
    print('App:', app['id'], app['attributes'].get('name'))
    infos = call('GET', f"/apps/{app['id']}/appInfos")['data']
    for info in infos:
        state = info['attributes'].get('state') or info['attributes'].get('appStoreState')
        print('AppInfo', info['id'], state)
        locs = call('GET', f"/appInfos/{info['id']}/appInfoLocalizations")['data']
        have = {l['attributes']['locale']: l for l in locs}
        for locale, loc in have.items():
            subtitle = os.environ['SUBTITLE_TR'] if locale.startswith('tr') else os.environ['SUBTITLE_EN']
            attrs = {'name': os.environ['APP_NAME'], 'subtitle': subtitle, 'privacyPolicyUrl': os.environ['PRIVACY_URL']}
            result = call('PATCH', f"/appInfoLocalizations/{loc['id']}",
                          {'data': {'type': 'appInfoLocalizations', 'id': loc['id'], 'attributes': attrs}})
            print(f"::notice title=asc {locale}::{'updated' if result else 'FAILED'} -> {attrs['name']}")
        if not any(l.startswith('tr') for l in have):
            result = call('POST', '/appInfoLocalizations', {'data': {'type': 'appInfoLocalizations',
                'attributes': {'locale': 'tr', 'name': os.environ['APP_NAME'], 'subtitle': os.environ['SUBTITLE_TR'],
                               'privacyPolicyUrl': os.environ['PRIVACY_URL']},
                'relationships': {'appInfo': {'data': {'type': 'appInfos', 'id': info['id']}}}}})
            print(f"::notice title=asc tr::{'added' if result else 'not added'}")
    after = call('GET', f"/apps/{app['id']}")
    print(f"::notice title=asc name::{after['data']['attributes'].get('name') if after else '?'}")


if __name__ == '__main__':
    main()
