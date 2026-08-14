# CLI Libby Dashboard / KOReader Libby Core

This repository is the shared development home for a Libby client that can be exercised from Python and Lua, with the Lua implementation intended to become the core of a self-contained KOReader plugin.

## Product goal

The final KOReader plugin should let a user:

- authenticate by generating the modern 8-digit Libby pointer setup code on the new device;
- view linked library cards;
- browse current loans as a list or cover grid;
- show loan time remaining next to each title;
- download the Adobe EPUB/PDF ACSM for a selected loan directly on the reader;
- register itself as an `.acsm` handler;
- manage Libby credentials independently from Adobe registration state.

The validated Libby protocol is documented in `LIBBY_CURRENT_PROTOCOL_HANDOFF.md`.

## Credential and registration settings

Libby and Adobe state are intentionally separate.

### Libby

The UI must provide:

- connection status;
- generate/re-authenticate setup code;
- reset Libby credentials.

Resetting Libby credentials removes the persisted Libby identity and all temporary setup state, but does not touch Adobe registration.

### Adobe registration

The UI must provide:

- registration status;
- export Adobe registration;
- import Adobe registration;
- reset Adobe registration.

The portable Adobe registration profile is versioned and contains the fields used by the validated `acsm.koplugin` activation implementation: `deviceKey`, `privateLicenseKey`, `licenseCert`, `user`, `username`, `pkcs12`, `deviceUUID`, `fingerprint`, `authCert`, and `activationURL`.

Export/import is important for users with multiple e-readers. A loan fulfilled under one anonymous Adobe authorization can be rejected when another independently-created anonymous authorization attempts to fulfill the same entitlement. Devices that intentionally share the same Adobe registration profile can present the same authorization identity instead of creating unrelated anonymous registrations.

Adobe registration exports contain private credentials and must be treated as sensitive. The UI should warn before reset or export. Resetting Adobe registration must not silently delete Libby credentials.

## Current source layout

```text
lua/
  adobe_profile.lua    portable Adobe registration profile validation/reset
  libby_state.lua      Libby credential state, loan time, Adobe format helpers
  spec/                Lua 5.1-compatible tests

python/
  libby_dashboard/
    state.py            Python reference implementation of the same state rules
  tests/
```

## Development runtimes

Lua compatibility target is Lua 5.1 / LuaJIT. On the current development machine:

```text
wsl bash -lc "/usr/bin/lua5.1 lua/spec/state_test.lua"
```

The Python implementation serves as a protocol/debugging reference; the Lua implementation is the basis for the eventual KOReader UI.

## ACSM boundary

The Libby client can legitimately stop at downloading the ACSM returned by the loan fulfillment flow. Adobe activation/fulfillment is kept as a separate internal subsystem so `.acsm` handling can also work for manually supplied ACSM files and so Libby account reset does not affect Adobe registration.
