from __future__ import annotations

from dataclasses import dataclass
from math import ceil
from typing import Any, Mapping, MutableMapping

SECONDS_PER_DAY = 24 * 60 * 60
ADOBE_PROFILE_VERSION = 1

ADOBE_REQUIRED_FIELDS = (
    "deviceKey",
    "privateLicenseKey",
    "user",
    "pkcs12",
    "deviceUUID",
    "fingerprint",
)

ADOBE_OPTIONAL_FIELDS = (
    "licenseCert",
    "username",
    "authCert",
    "activationURL",
)


def reset_libby_credentials(state: MutableMapping[str, Any]) -> bool:
    had_identity = state.get("libby_identity") is not None
    for key in (
        "libby_identity",
        "pending_identity",
        "pending_setup_code",
        "pending_blessing",
    ):
        state.pop(key, None)
    return had_identity


def is_libby_authenticated(state: Mapping[str, Any]) -> bool:
    identity = state.get("libby_identity")
    return isinstance(identity, str) and bool(identity)


def days_remaining(expire_timestamp: float, now_timestamp: float) -> int:
    seconds = expire_timestamp - now_timestamp
    if seconds <= 0:
        return 0
    return ceil(seconds / SECONDS_PER_DAY)


def adobe_formats(loan: Mapping[str, Any]) -> list[str]:
    result: list[str] = []
    for item in loan.get("formats") or []:
        if not isinstance(item, Mapping):
            continue
        format_id = item.get("id")
        if format_id in {"ebook-epub-adobe", "ebook-pdf-adobe"}:
            result.append(str(format_id))
    return result


def preferred_adobe_format(loan: Mapping[str, Any]) -> str | None:
    formats = adobe_formats(loan)
    if "ebook-epub-adobe" in formats:
        return "ebook-epub-adobe"
    return formats[0] if formats else None


@dataclass(frozen=True)
class AdobeProfileSummary:
    registered: bool
    profile_version: int | None = None
    user: str | None = None
    username: str | None = None
    device_uuid: str | None = None
    activation_url: str | None = None


def normalize_adobe_profile(profile: Mapping[str, Any]) -> dict[str, Any]:
    version = profile.get("profileVersion", ADOBE_PROFILE_VERSION)
    if version != ADOBE_PROFILE_VERSION:
        raise ValueError(f"Unsupported Adobe registration profile version: {version}")

    for key in ADOBE_REQUIRED_FIELDS:
        value = profile.get(key)
        if not isinstance(value, str) or not value:
            raise ValueError(f"Adobe registration profile is missing {key}")

    normalized: dict[str, Any] = {"profileVersion": ADOBE_PROFILE_VERSION}
    for key in ADOBE_REQUIRED_FIELDS + ADOBE_OPTIONAL_FIELDS:
        normalized[key] = profile.get(key)
    return normalized


def adobe_profile_summary(profile: Mapping[str, Any] | None) -> AdobeProfileSummary:
    if profile is None:
        return AdobeProfileSummary(registered=False)
    try:
        normalized = normalize_adobe_profile(profile)
    except ValueError:
        return AdobeProfileSummary(registered=False)

    return AdobeProfileSummary(
        registered=True,
        profile_version=normalized["profileVersion"],
        user=normalized["user"],
        username=normalized.get("username"),
        device_uuid=normalized["deviceUUID"],
        activation_url=normalized.get("activationURL"),
    )


def reset_adobe_registration(state: MutableMapping[str, Any]) -> bool:
    had_profile = state.get("adobe_registration") is not None
    state.pop("adobe_registration", None)
    return had_profile
