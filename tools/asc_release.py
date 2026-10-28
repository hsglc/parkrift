"""Prepares the App Store release through the App Store Connect API and submits it for review.
Run by .github/workflows/release.yml. Every step prints what it did; steps that cannot be done
through the API (or miss information) end in a ::warning:: naming what is left to do by hand.

Steps: Game Center leaderboards · categories · version 1.0 · store texts (EN, TR, ES) ·
age rating · screenshots · build · review details · submission.

Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, BUNDLE_ID, SHOTS (folder of landscape PNGs),
     REVIEW_PHONE (optional), SUBMIT=1 to submit.
"""
import os, sys, time, json, hashlib
import jwt, requests

API = 'https://api.appstoreconnect.apple.com'
LEFT = []


def token():
    key = open(os.environ['ASC_KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode({'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'},
                      key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, path, body=None, quiet=False):
    url = path if path.startswith('http') else API + path
    r = requests.request(method, url, headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'},
                         data=json.dumps(body) if body is not None else None, timeout=90)
    if r.status_code >= 400:
        if not quiet:
            print(f'::warning::{method} {path} -> {r.status_code}: {r.text[:900]}')
        return None
    return r.json() if r.text else {}


def left(text):
    LEFT.append(text)
    print('::warning title=left to do::' + text)


# ------------------------------------------------------------------ texts

TEXTS = {
    'en-US': dict(
        description=(
            "Park, drift and race through a living city!\n\n"
            "Parkrift is a fast arcade car game for one or two players. Squeeze into tight bays, slide "
            "into your spot with a drift, outrun the police and race a friend across town.\n\n"
            "• 50 parking levels that get harder every level: time limits, crash limits, back-in bays, wet ground and patrol cars\n"
            "• City park races and car races with traffic, pedestrians, ramps and shortcuts\n"
            "• Real drift: handbrake, throttle and counter-steer\n"
            "• Police chases: crash, speed or hit someone and the sirens come for you\n"
            "• Day, night and rain\n"
            "• 6 original cars to unlock, with paint, rims and upgrades\n"
            "• Daily tasks, a daily gift streak and weekend double coins\n"
            "• Play online with a friend by room code, or quick match a random driver\n"
            "• Beat your own ghost on every level\n"
            "• Game Center leaderboards\n\n"
            "No ads, no accounts, no tracking."),
        keywords='parking,car,drift,racing,police,chase,multiplayer,online,driving,city,arcade,simulator,park,cars',
        promotionalText='50 parking levels, real drift, police chases and online races with a friend. Weekend: double coins!',
    ),
    'tr': dict(
        description=(
            "Canlı bir şehirde park et, drift at, yarış!\n\n"
            "Parkrift tek ya da iki kişilik hızlı bir arcade araba oyunu. Dar yerlere sığ, park yerine "
            "drift atarak gir, polisten kaç ve şehirde arkadaşınla yarış.\n\n"
            "• Her bölümde zorlaşan 50 park bölümü: süre ve çarpma sınırı, geri geri park, kaygan zemin, devriye araçlar\n"
            "• Trafik, yaya, rampa ve kestirme yollarla şehirde park ve araba yarışları\n"
            "• Gerçek drift: el freni, gaz ve ters direksiyon\n"
            "• Polis kovalamacası: kaza yap, hız yap ya da yayaya çarp, siren peşine düşsün\n"
            "• Gündüz, gece ve yağmur\n"
            "• Boya, jant ve geliştirmeleriyle açılacak 6 özgün araba\n"
            "• Günlük görevler, günlük hediye serisi ve hafta sonu 2x para\n"
            "• Oda koduyla arkadaşınla ya da hızlı eşleşmeyle rastgele bir rakiple online oyna\n"
            "• Her bölümde kendi hayaletini geç\n"
            "• Game Center sıralamaları\n\n"
            "Reklam yok, hesap yok, takip yok."),
        keywords='park,araba,drift,yarış,polis,kovalamaca,online,çok oyunculu,sürüş,şehir,arcade,simülasyon,otopark',
        promotionalText='50 park bölümü, gerçek drift, polis kovalamacası ve arkadaşınla online yarış. Hafta sonu 2x para!',
    ),
    'es-ES': dict(
        description=(
            "¡Aparca, derrapa y compite en una ciudad viva!\n\n"
            "Parkrift es un juego de coches arcade para uno o dos jugadores. Mete el coche en plazas "
            "estrechas, entra derrapando, escapa de la policía y corre contra un amigo por la ciudad.\n\n"
            "• 50 niveles de aparcamiento cada vez más difíciles\n"
            "• Carreras de aparcamiento y de coches con tráfico, peatones, rampas y atajos\n"
            "• Derrape real: freno de mano, acelerador y contravolante\n"
            "• Persecuciones policiales\n"
            "• Día, noche y lluvia\n"
            "• 6 coches originales para desbloquear, con pintura, llantas y mejoras\n"
            "• Tareas diarias, regalo diario y monedas dobles el fin de semana\n"
            "• Juega online con un amigo o en partida rápida\n"
            "• Supera a tu fantasma en cada nivel\n\n"
            "Sin anuncios, sin cuentas, sin seguimiento."),
        keywords='aparcar,coche,derrape,carreras,policía,persecución,online,multijugador,conducir,ciudad,arcade',
        promotionalText='50 niveles, derrape real, persecuciones y carreras online con amigos. ¡Monedas dobles el finde!',
    ),
}
SUPPORT_URL = 'https://parkrift.huseyinglc0-946.workers.dev/support'
SUBTITLES = {'en-US': 'Park, Drift & Race Online', 'tr': 'Park Et, Drift At, Yarış', 'es-ES': 'Aparca, derrapa y compite'}

LEADERBOARDS = [
    # vendor id, reference name, sort, formatter, names (en, tr, es)
    ('parkrift.stars', 'Total stars', 'DESC', 'INTEGER', ('Total Stars', 'Toplam Yıldız', 'Estrellas totales')),
    ('parkrift.drift', 'Best drift', 'DESC', 'INTEGER', ('Best Drift', 'En İyi Drift', 'Mejor derrape')),
    ('parkrift.wins', 'Wins', 'DESC', 'INTEGER', ('Wins', 'Galibiyet', 'Victorias')),
]


def main():
    apps = call('GET', f"/v1/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")
    if not apps or not apps['data']:
        print('::error::App not found'); sys.exit(1)
    app = apps['data'][0]
    app_id = app['id']
    print('App', app_id, app['attributes'].get('name'))

    game_center(app_id)
    app_info(app_id)
    version = ensure_version(app_id)
    if not version:
        left('App Store version could not be created'); return finish()
    vid = version['id']
    texts(vid)
    age_rating(app_id)
    call('PATCH', f'/v1/apps/{app_id}', {'data': {'type': 'apps', 'id': app_id,
        'attributes': {'contentRightsDeclaration': 'USES_THIRD_PARTY_CONTENT'}}})
    screenshots(vid)
    build_ok = attach_build(app_id, vid)
    review_ok = review_details(vid)
    if os.environ.get('SUBMIT') == '1' and build_ok and review_ok:
        submit(app_id, vid)
    finish()


def finish():
    print('\n==== SUMMARY ====')
    if LEFT:
        for item in LEFT:
            print('::notice title=left::' + item)
    else:
        print('::notice title=release::everything done')


# ------------------------------------------------------------------ steps

def game_center(app_id):
    detail = call('GET', f'/v1/apps/{app_id}/gameCenterDetail', quiet=True)
    gc_id = detail['data']['id'] if detail and detail.get('data') else None
    if not gc_id:
        made = call('POST', '/v1/gameCenterDetails', {'data': {'type': 'gameCenterDetails',
            'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})
        gc_id = made['data']['id'] if made else None
    if not gc_id:
        left('Game Center could not be turned on for the app'); return
    print('Game Center detail', gc_id)
    have = call('GET', f'/v1/gameCenterDetails/{gc_id}/gameCenterLeaderboards?limit=50') or {'data': []}
    existing = {l['attributes'].get('vendorIdentifier'): l['id'] for l in have['data']}
    for vendor, ref, sort, fmt, names in LEADERBOARDS:
        lid = existing.get(vendor)
        if not lid:
            made = call('POST', '/v1/gameCenterLeaderboards', {'data': {'type': 'gameCenterLeaderboards',
                'attributes': {'referenceName': ref, 'vendorIdentifier': vendor, 'defaultFormatter': fmt,
                               'submissionType': 'BEST_SCORE', 'scoreSortType': sort},
                'relationships': {'gameCenterDetail': {'data': {'type': 'gameCenterDetails', 'id': gc_id}}}}})
            lid = made['data']['id'] if made else None
            print('leaderboard', vendor, 'created' if lid else 'FAILED')
        if not lid:
            continue
        locs = call('GET', f'/v1/gameCenterLeaderboards/{lid}/localizations') or {'data': []}
        have_locales = {l['attributes']['locale'] for l in locs['data']}
        for locale, name in zip(['en-US', 'tr', 'es-ES'], names):
            if locale not in have_locales:
                call('POST', '/v1/gameCenterLeaderboardLocalizations', {'data': {'type': 'gameCenterLeaderboardLocalizations',
                    'attributes': {'locale': locale, 'name': name},
                    'relationships': {'gameCenterLeaderboard': {'data': {'type': 'gameCenterLeaderboards', 'id': lid}}}}})


def app_info(app_id):
    infos = call('GET', f'/v1/apps/{app_id}/appInfos')
    if not infos:
        return
    for info in infos['data']:
        iid = info['id']
        call('PATCH', f'/v1/appInfos/{iid}', {'data': {'type': 'appInfos', 'id': iid, 'relationships': {
            'primaryCategory': {'data': {'type': 'appCategories', 'id': 'GAMES'}},
            'primarySubcategoryOne': {'data': {'type': 'appCategories', 'id': 'GAMES_RACING'}},
            'primarySubcategoryTwo': {'data': {'type': 'appCategories', 'id': 'GAMES_SIMULATION'}}}}})
        locs = call('GET', f'/v1/appInfos/{iid}/appInfoLocalizations') or {'data': []}
        have = {l['attributes']['locale']: l['id'] for l in locs['data']}
        # Keep the app's name as it is (it went through the name check already)
        name = next((l['attributes'].get('name') for l in locs['data'] if l['attributes'].get('name')), 'Parkrift')
        for locale, subtitle in SUBTITLES.items():
            attrs = {'subtitle': subtitle, 'privacyPolicyUrl': 'https://parkrift.huseyinglc0-946.workers.dev/privacy'}
            if locale not in have:
                attrs['name'] = name
            if locale in have:
                call('PATCH', f'/v1/appInfoLocalizations/{have[locale]}', {'data': {'type': 'appInfoLocalizations',
                    'id': have[locale], 'attributes': attrs}})
            else:
                call('POST', '/v1/appInfoLocalizations', {'data': {'type': 'appInfoLocalizations',
                    'attributes': dict(attrs, locale=locale),
                    'relationships': {'appInfo': {'data': {'type': 'appInfos', 'id': iid}}}}})
        print('app info', iid, 'categories and subtitles set')


def ensure_version(app_id):
    versions = call('GET', f'/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=10') or {'data': []}
    for v in versions['data']:
        state = v['attributes'].get('appStoreState') or v['attributes'].get('appVersionState')
        print('version', v['attributes']['versionString'], state)
        if state in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED', 'INVALID_BINARY'):
            return v
        if state in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'READY_FOR_REVIEW'):
            left(f"version {v['attributes']['versionString']} is already {state}")
            return None
    made = call('POST', '/v1/appStoreVersions', {'data': {'type': 'appStoreVersions',
        'attributes': {'platform': 'IOS', 'versionString': '1.0'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})
    return made['data'] if made else None


def texts(vid):
    locs = call('GET', f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations') or {'data': []}
    have = {l['attributes']['locale']: l['id'] for l in locs['data']}
    for locale, t in TEXTS.items():
        attrs = dict(t, supportUrl=SUPPORT_URL, marketingUrl=SUPPORT_URL)
        if locale in have:
            ok = call('PATCH', f'/v1/appStoreVersionLocalizations/{have[locale]}', {'data': {
                'type': 'appStoreVersionLocalizations', 'id': have[locale], 'attributes': attrs}})
        else:
            ok = call('POST', '/v1/appStoreVersionLocalizations', {'data': {'type': 'appStoreVersionLocalizations',
                'attributes': dict(attrs, locale=locale),
                'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}}}})
        print('texts', locale, 'ok' if ok is not None else 'FAILED')


def age_rating(app_id):
    infos = call('GET', f'/v1/apps/{app_id}/appInfos') or {'data': []}
    for info in infos['data']:
        dec = call('GET', f"/v1/appInfos/{info['id']}/ageRatingDeclaration")
        if not dec or not dec.get('data'):
            continue
        did = dec['data']['id']
        attrs = {}
        for key, value in dec['data']['attributes'].items():
            if key in ('kidsAgeBand', 'ageRatingOverride', 'ageRatingOverrideV2', 'koreaAgeRatingOverride', 'developerAgeRatingInfoUrl'):
                continue
            if isinstance(value, bool) or value is None and key.startswith(('is', 'has', 'unrestricted', 'gambling',
                    'seventeen', 'lootBox', 'messaging', 'parental', 'userGenerated', 'advertising', 'ageAssurance',
                    'healthOrWellness')):
                attrs[key] = False
            elif isinstance(value, str) or value is None:
                attrs[key] = 'NONE'
        # A car game with crashes: cartoon violence, rare
        if 'violenceCartoonOrFantasy' in attrs:
            attrs['violenceCartoonOrFantasy'] = 'INFREQUENT_OR_MILD'
        ok = call('PATCH', f'/v1/ageRatingDeclarations/{did}', {'data': {'type': 'ageRatingDeclarations', 'id': did,
                                                                        'attributes': attrs}})
        if ok is None:
            # Field by field, trying the other type when Apple refuses the first guess
            for key, value in attrs.items():
                for attempt in (value, 'NONE' if isinstance(value, bool) else False):
                    done = call('PATCH', f'/v1/ageRatingDeclarations/{did}', {'data': {'type': 'ageRatingDeclarations',
                        'id': did, 'attributes': {key: attempt}}}, quiet=True)
                    if done is not None:
                        break
                else:
                    print(f'::warning::age rating field {key} not set')
        print('age rating set')


def screenshots(vid):
    folder = os.environ.get('SHOTS', '')

    def shots_for(locale):
        # One set per language (SHOTS/<locale>/), else the shared folder
        for place in (os.path.join(folder, locale), folder):
            if place and os.path.isdir(place):
                found = sorted(os.path.join(place, f) for f in os.listdir(place) if f.endswith('.png'))
                if found:
                    return found
        return []
    if not shots_for('en-US'):
        left('no screenshots were made'); return
    locs = call('GET', f'/v1/appStoreVersions/{vid}/appStoreVersionLocalizations') or {'data': []}
    for loc in locs['data']:
        lid = loc['id']
        sets = call('GET', f'/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets') or {'data': []}
        target = None
        for s in sets['data']:
            if s['attributes']['screenshotDisplayType'] == 'APP_IPHONE_67':
                target = s['id']
        if target:
            old = call('GET', f'/v1/appScreenshotSets/{target}/appScreenshots') or {'data': []}
            for shot in old['data']:
                call('DELETE', f"/v1/appScreenshots/{shot['id']}", quiet=True)
        else:
            made = call('POST', '/v1/appScreenshotSets', {'data': {'type': 'appScreenshotSets',
                'attributes': {'screenshotDisplayType': 'APP_IPHONE_67'},
                'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': lid}}}}})
            target = made['data']['id'] if made else None
        if not target:
            left(f"screenshot set for {loc['attributes']['locale']} failed"); continue
        uploaded = 0
        files = shots_for(loc['attributes']['locale'])
        for path in files[:10]:
            name = os.path.basename(path)
            data = open(path, 'rb').read()
            res = call('POST', '/v1/appScreenshots', {'data': {'type': 'appScreenshots',
                'attributes': {'fileName': name, 'fileSize': len(data)},
                'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': target}}}}})
            if not res:
                continue
            sid = res['data']['id']
            for op in res['data']['attributes'].get('uploadOperations') or []:
                chunk = data[op['offset']:op['offset'] + op['length']]
                headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
                requests.request(op['method'], op['url'], headers=headers, data=chunk, timeout=120)
            done = call('PATCH', f'/v1/appScreenshots/{sid}', {'data': {'type': 'appScreenshots', 'id': sid,
                'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(data).hexdigest()}}})
            uploaded += 1 if done else 0
        print('screenshots', loc['attributes']['locale'], uploaded, 'of', min(10, len(files)))
        if uploaded == 0:
            left(f"screenshots for {loc['attributes']['locale']} did not upload")


def attach_build(app_id, vid):
    builds = call('GET', f'/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5&filter[processingState]=VALID') or {'data': []}
    if not builds['data']:
        left('no processed build to attach'); return False
    build = builds['data'][0]
    bid = build['id']
    call('PATCH', f'/v1/builds/{bid}', {'data': {'type': 'builds', 'id': bid,
                                                  'attributes': {'usesNonExemptEncryption': False}}}, quiet=True)
    ok = call('PATCH', f'/v1/appStoreVersions/{vid}/relationships/build', {'data': {'type': 'builds', 'id': bid}})
    print('build', build['attributes'].get('version'), 'attached' if ok is not None else 'FAILED')
    return ok is not None


def review_details(vid):
    phone = os.environ.get('REVIEW_PHONE', '').strip()
    existing = call('GET', f'/v1/appStoreVersions/{vid}/appStoreReviewDetail', quiet=True)
    attrs = {'contactFirstName': 'Hüseyin', 'contactLastName': 'Gülcü', 'contactEmail': 'huseyinglc0@gmail.com',
             'demoAccountRequired': False,
             'notes': ('No account or login exists in this app; everything works right away. '
                       'Solo: Park Master (50 levels) and City (car race, park race) need no network. '
                       'Online (Play with a friend): tap Create Room on one device and Join Room with the 4-letter code '
                       'on a second device, or Quick Match on two devices at about the same time. If no opponent is '
                       'found within a minute, Quick Match starts a solo race against the city traffic instead. '
                       'Online play only relays car positions between the two players; there is no chat, no text '
                       'entry other than the room code, and no user-generated content. Game Center (leaderboards) is '
                       'optional. Coins are earned in play only; there are no in-app purchases or ads.')}
    if phone:
        attrs['contactPhone'] = phone
    if existing and existing.get('data'):
        rid = existing['data']['id']
        have_phone = existing['data']['attributes'].get('contactPhone')
        call('PATCH', f'/v1/appStoreReviewDetails/{rid}', {'data': {'type': 'appStoreReviewDetails', 'id': rid, 'attributes': attrs}})
    else:
        have_phone = None
        call('POST', '/v1/appStoreReviewDetails', {'data': {'type': 'appStoreReviewDetails', 'attributes': attrs,
            'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}}}})
    if not phone and not have_phone:
        left('App Review contact phone number is missing (App Store Connect > the version > App Review Information)')
        return False
    return True


def submit(app_id, vid):
    sub = call('POST', '/v1/reviewSubmissions', {'data': {'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})
    if not sub:
        left('review submission could not be created'); return
    sid = sub['data']['id']
    item = call('POST', '/v1/reviewSubmissionItems', {'data': {'type': 'reviewSubmissionItems',
        'relationships': {'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sid}},
                          'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': vid}}}}})
    if not item:
        left('version could not be added to the submission (see the warning above for what Apple says is missing)'); return
    done = call('PATCH', f'/v1/reviewSubmissions/{sid}', {'data': {'type': 'reviewSubmissions', 'id': sid,
                                                                  'attributes': {'submitted': True}}})
    if done:
        print('::notice title=release::Submitted for App Review')
    else:
        left('submission was refused (see the warning above)')


if __name__ == '__main__':
    main()
