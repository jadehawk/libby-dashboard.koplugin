import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from libby_dashboard.state import (  # noqa: E402
    adobe_profile_summary,
    days_remaining,
    normalize_adobe_profile,
    preferred_adobe_format,
    reset_adobe_registration,
    reset_libby_credentials,
)


def valid_profile():
    return {
        "deviceKey": "device-key",
        "privateLicenseKey": "private-key",
        "licenseCert": "license-cert",
        "user": "urn:uuid:user",
        "username": "anonymous",
        "pkcs12": "pkcs12-data",
        "deviceUUID": "device-uuid",
        "fingerprint": "fingerprint",
        "authCert": "auth-cert",
        "activationURL": "https://example.invalid/adept",
    }


def test_reset_libby_credentials_clears_pending_state():
    state = {
        "libby_identity": "identity",
        "pending_identity": "pending",
        "pending_setup_code": "12345678",
        "pending_blessing": "blessing",
    }
    assert reset_libby_credentials(state) is True
    assert state == {}


def test_days_remaining_rounds_partial_days_up():
    assert days_remaining(1001, 1000) == 1
    assert days_remaining(1000 + 2 * 86400, 1000) == 2
    assert days_remaining(999, 1000) == 0


def test_preferred_adobe_format_prefers_epub():
    loan = {
        "formats": [
            {"id": "ebook-pdf-adobe"},
            {"id": "ebook-epub-adobe"},
        ]
    }
    assert preferred_adobe_format(loan) == "ebook-epub-adobe"


def test_adobe_profile_round_trip_shape():
    normalized = normalize_adobe_profile(valid_profile())
    assert normalized["profileVersion"] == 1
    assert normalized["deviceUUID"] == "device-uuid"
    summary = adobe_profile_summary(normalized)
    assert summary.registered is True
    assert summary.device_uuid == "device-uuid"


def test_adobe_profile_requires_pkcs12():
    profile = valid_profile()
    del profile["pkcs12"]
    try:
        normalize_adobe_profile(profile)
    except ValueError as exc:
        assert "pkcs12" in str(exc)
    else:
        raise AssertionError("expected invalid profile")


def test_reset_adobe_registration():
    state = {"adobe_registration": valid_profile()}
    assert reset_adobe_registration(state) is True
    assert state == {}
