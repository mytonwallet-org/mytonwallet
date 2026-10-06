import base64
import ctypes
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request

TARGET_REPOSITORY = 'ton-blockchain/ton-wallet'
TARGET_KEY_ID = '3380204578043523366'
TARGET_PUBLIC_KEY = 'bDc3RK3tVOcPYMbf5HPY3sh/GUdmslzr1FjkO3eHkyk='
ITEM_ID = 'nphplpgoakhhjchkkhmiggakijnkhfnd'
ITEM_NAME = f'publishers/c32caf27-4035-477c-b112-caad6c385511/items/{ITEM_ID}'
ITEM_URL = f'https://chromewebstore.googleapis.com/v2/{ITEM_NAME}:fetchStatus'
SCOPE = 'https://www.googleapis.com/auth/chromewebstore'
SECRET_NAMES = ('GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN')
OUTPUT_NAME = 'gram-publisher-bootstrap.json'
ERROR_REASONS = frozenset(('SERVICE_DISABLED', 'ACCESS_TOKEN_SCOPE_INSUFFICIENT', 'IAM_PERMISSION_DENIED',
                           'CONSUMER_INVALID', 'USER_PROJECT_DENIED', 'BILLING_DISABLED', 'PERMISSION_DENIED',
                           'insufficientPermissions', 'forbidden'))


class BootstrapError(Exception):
    def __init__(self, stage, status=0, reason=None):
        self.stage = stage
        self.status = status
        self.reason = reason if reason in ERROR_REASONS else None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        return None


def request_json(stage, request):
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(request, timeout=20) as response:
            if response.status != 200:
                raise BootstrapError(stage, response.status)
            body = response.read(1_048_577)
        if len(body) > 1_048_576:
            raise BootstrapError(stage)
        value = json.loads(body)
        if not isinstance(value, dict):
            raise BootstrapError(stage)
        return value
    except urllib.error.HTTPError as error:
        status = error.code
        reason = None
        try:
            body = json.loads(error.read(16_384)).get('error', {})
            entries = body.get('details', []) + body.get('errors', [])
            reason = next((entry.get('reason') for entry in entries
                           if isinstance(entry, dict) and entry.get('reason') in ERROR_REASONS), None)
            reason = reason or (body.get('status') if body.get('status') in ERROR_REASONS else None)
        except Exception:
            pass
        finally:
            error.close()
        raise BootstrapError(stage, status, reason) from None
    except BootstrapError:
        raise
    except Exception:
        raise BootstrapError(stage) from None


def seal(sodium, public_key, plaintext):
    message = ctypes.create_string_buffer(plaintext)
    ciphertext = ctypes.create_string_buffer(len(plaintext) + 48)
    if sodium.crypto_box_seal(ciphertext, message, len(plaintext), public_key) != 0:
        raise BootstrapError('seal')
    return ciphertext.raw


def runtime():
    try:
        public_key = base64.b64decode(TARGET_PUBLIC_KEY, validate=True)
        if len(public_key) != 32:
            raise BootstrapError('runtime')
        sodium = ctypes.CDLL('/usr/lib/x86_64-linux-gnu/libsodium.so.23')
        sodium.sodium_init.restype = ctypes.c_int
        if sodium.sodium_init() < 0:
            raise BootstrapError('runtime')
        for name, expected in [('crypto_box_publickeybytes', 32), ('crypto_box_secretkeybytes', 32),
                               ('crypto_box_sealbytes', 48)]:
            function = getattr(sodium, name)
            function.restype = ctypes.c_size_t
            if function() != expected:
                raise BootstrapError('runtime')
        sodium.crypto_box_keypair.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        sodium.crypto_box_keypair.restype = ctypes.c_int
        sodium.crypto_box_seal.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong, ctypes.c_void_p]
        sodium.crypto_box_seal.restype = ctypes.c_int
        sodium.crypto_box_seal_open.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ulonglong,
                                               ctypes.c_void_p, ctypes.c_void_p]
        sodium.crypto_box_seal_open.restype = ctypes.c_int
        test_public = ctypes.create_string_buffer(32)
        test_private = ctypes.create_string_buffer(32)
        if sodium.crypto_box_keypair(test_public, test_private) != 0:
            raise BootstrapError('runtime')
        message = b'Gram publisher encryption self-test'
        ciphertext = seal(sodium, test_public, message)
        decrypted = ctypes.create_string_buffer(len(message))
        if sodium.crypto_box_seal_open(decrypted, ciphertext, len(ciphertext), test_public, test_private) != 0:
            raise BootstrapError('runtime')
        if decrypted.raw != message:
            raise BootstrapError('runtime')
        return sodium, ctypes.create_string_buffer(public_key, 32)
    except BootstrapError:
        raise
    except Exception:
        raise BootstrapError('runtime') from None


def bootstrap(sodium, public_key, output):
    credentials = {name: os.environ.get(name, '') for name in SECRET_NAMES}
    if not all(credentials.values()):
        raise BootstrapError('credentials')
    form = urllib.parse.urlencode({
        'client_id': credentials['GOOGLE_CLIENT_ID'],
        'client_secret': credentials['GOOGLE_CLIENT_SECRET'],
        'refresh_token': credentials['GOOGLE_REFRESH_TOKEN'],
        'grant_type': 'refresh_token',
    }).encode()
    token = request_json('oauth', urllib.request.Request(
        'https://oauth2.googleapis.com/token', data=form,
        headers={'Content-Type': 'application/x-www-form-urlencoded'},
    ))
    access_token = token.get('access_token')
    if not isinstance(access_token, str) or not access_token or token.get('token_type', '').lower() != 'bearer':
        raise BootstrapError('oauth')
    info = request_json('tokeninfo', urllib.request.Request(
        'https://oauth2.googleapis.com/tokeninfo?' + urllib.parse.urlencode({'access_token': access_token}),
    ))
    scope = info.get('scope')
    if not isinstance(scope, str) or SCOPE not in scope.split():
        raise BootstrapError('scope')
    try:
        status = request_json('store', urllib.request.Request(
            ITEM_URL, headers={'Authorization': f'Bearer {access_token}'},
        ))
    except BootstrapError as error:
        if error.status == 403:
            for stage, item_id in [('legacy_target', ITEM_ID),
                                   ('legacy_control', 'fldfpgipfncgndfolcbkdeeknbbbnhcc')]:
                try:
                    item = request_json(stage, urllib.request.Request(
                        f'https://www.googleapis.com/chromewebstore/v1.1/items/{item_id}?projection=DRAFT',
                        headers={'Authorization': f'Bearer {access_token}', 'x-goog-api-version': '2'},
                    ))
                    result = 200 if item.get('id') == item_id else 0
                except BootstrapError as probe_error:
                    result = probe_error.status
                print(f'stage={stage} status={result}')
        raise
    if status.get('name') != ITEM_NAME or status.get('itemId') != ITEM_ID:
        raise BootstrapError('item')
    artifact = {
        'repository': TARGET_REPOSITORY,
        'key_id': TARGET_KEY_ID,
        'source_sha': os.environ['GITHUB_SHA'],
        'run_id': os.environ['GITHUB_RUN_ID'],
        'run_attempt': os.environ['GITHUB_RUN_ATTEMPT'],
        'item_name': ITEM_NAME,
        'secrets': {name: base64.b64encode(seal(sodium, public_key, credentials[name].encode())).decode()
                    for name in SECRET_NAMES},
    }
    with output.open('x') as file:
        json.dump(artifact, file)
        file.write('\n')


def main(argv=None):
    output = None
    try:
        mode = (sys.argv[1:] if argv is None else argv)
        if mode not in [['self-test'], ['seal']]:
            raise BootstrapError('arguments')
        output = Path(os.environ['RUNNER_TEMP']) / OUTPUT_NAME
        output.unlink(missing_ok=True)
        sodium, public_key = runtime()
        if mode == ['seal']:
            bootstrap(sodium, public_key, output)
        print('stage=complete status=200')
        return 0
    except Exception as error:
        if output is not None:
            output.unlink(missing_ok=True)
        stage = error.stage if isinstance(error, BootstrapError) else 'bootstrap'
        status = error.status if isinstance(error, BootstrapError) else 0
        reason = error.reason if isinstance(error, BootstrapError) else None
        print(f'stage={stage} status={status}' + (f' reason={reason}' if reason else ''))
        return 1


if __name__ == '__main__':
    sys.exit(main())
