import datetime
import os
import plistlib
import sys
import tempfile
import argparse
import base64

from BuildEnvironment import run_executable_with_output
from GenerateProfiles import (
    cleanup_temp_keychain,
    get_certificate_base64_from_p12,
    get_signing_identity_from_p12,
    setup_temp_keychain,
)


def read_profile(path):
    decoded = run_executable_with_output('security', arguments=['cms', '-D', '-i', path], check_result=True)
    if isinstance(decoded, bytes):
        return plistlib.loads(decoded)
    return plistlib.loads(decoded.encode('utf-8'))


def write_profile(profile, path, certificate_data, signing_identity, keychain_name):
    profile['CreationDate'] = datetime.datetime.utcnow().replace(microsecond=0)
    profile['DeveloperCertificates'] = [base64.b64decode(certificate_data)]

    # The signature of the source profile describes content that no longer exists once the
    # dates change, and it is rebuilt below with the fake identity, so drop it first.
    profile.pop('DER-Encoded-Profile', None)

    temporary_path = tempfile.mktemp()
    with open(temporary_path, 'wb') as file:
        plistlib.dump(profile, file, fmt=plistlib.FMT_XML)

    run_executable_with_output('security', arguments=[
        'cms', '-S', '-k', keychain_name, '-N', signing_identity, '-i', temporary_path, '-o', path
    ], check_result=True)

    os.unlink(temporary_path)


def refresh_profiles(source_path, destination_path, certs_path, validity_days):
    p12_path = os.path.join(certs_path, 'SelfSigned.p12')
    if not os.path.exists(p12_path):
        print('{} does not exist'.format(p12_path))
        sys.exit(1)

    if not os.path.exists(destination_path):
        os.makedirs(destination_path)

    certificate_data = get_certificate_base64_from_p12(p12_path, '')
    signing_identity = get_signing_identity_from_p12(p12_path, '')
    if not signing_identity:
        print('Could not extract signing identity from {}'.format(p12_path))
        sys.exit(1)

    print('Using signing identity: {}'.format(signing_identity))
    print('Profiles will stay valid for {} days'.format(validity_days))

    expiration = datetime.datetime.utcnow().replace(microsecond=0) + datetime.timedelta(days=validity_days)
    keychain_name = setup_temp_keychain(p12_path, '')

    try:
        refreshed = 0
        for file_name in sorted(os.listdir(source_path)):
            if not file_name.endswith('.mobileprovision'):
                continue
            source = os.path.join(source_path, file_name)
            destination = os.path.join(destination_path, file_name)
            profile = read_profile(source)
            profile['ExpirationDate'] = expiration
            write_profile(profile, destination, certificate_data, signing_identity, keychain_name)
            print('{} -> valid until {}'.format(file_name, expiration.isoformat()))
            refreshed += 1
        print('Refreshed {} profiles.'.format(refreshed))
    finally:
        cleanup_temp_keychain(keychain_name)


def main():
    parser = argparse.ArgumentParser(description='Extend the expiry of the self-signed verification profiles and re-sign them.')
    parser.add_argument('--source', required=True, help='Directory with .mobileprovision files to read.')
    parser.add_argument('--destination', required=True, help='Directory to write the refreshed profiles to.')
    parser.add_argument('--certsPath', required=False, default='build-system/fake-codesigning/certs', help='Directory containing SelfSigned.p12.')
    parser.add_argument('--validityDays', required=False, type=int, default=365, help='How long the refreshed profiles stay valid.')
    arguments = parser.parse_args()

    refresh_profiles(
        source_path=arguments.source,
        destination_path=arguments.destination,
        certs_path=arguments.certsPath,
        validity_days=arguments.validityDays
    )


if __name__ == '__main__':
    main()
