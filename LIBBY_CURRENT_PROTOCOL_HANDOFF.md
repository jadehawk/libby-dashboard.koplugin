# Current Libby Protocol Handoff

Last validated: 2026-08-13

Purpose: this document captures the working Libby authentication, account sync, loan discovery, and ACSM fulfillment flow that was reverse-engineered and validated in the `libby-downloader-calibre-plugin` project. It is intended to be sufficient context for implementing the same workflow on another platform (for example a KOReader Lua plugin) without repeating the discovery work.

This document deliberately contains **no real tokens, card IDs, loan IDs, setup codes, signed URLs, or user data**. Treat every Libby identity JWT and every signed ACSM URL as sensitive.

The implementation this document describes is the working code in:

- `calibre-plugin/libby/client.py`
- `calibre-plugin/config.py`
- `calibre-plugin/ebook_download.py`
- `tests/libby_client_tests.py`

## 1. Scope and important boundary

The working Libby flow has two separate jobs:

1. Authenticate a new client/device to an existing Libby account and obtain a persistent Libby identity JWT.
2. Use that identity to query the current account state and request fulfillment of currently borrowed loans.

For Adobe EPUB/PDF loans, Libby does **not** return the EPUB/PDF directly. It returns a JSON fulfillment response containing a short-lived, signed `fulfill.contentreserve.com` URL. Fetching that URL returns the actual `.acsm` XML payload.

An ACSM is an Adobe Content Server fulfillment token, not the final book. On Calibre, DeACSM handles the next step. A KOReader or other-platform implementation can stop after downloading the ACSM, hand it to another compatible component, or separately implement an appropriate Adobe-compatible fulfillment layer. The Libby portion described here does not need to remove or bypass the loan's Adobe DRM/time enforcement.

## 2. Current service endpoints

Current working Libby Sentry base URL:

```text
https://sentry.libbyapp.com/
```

Do **not** use the old `sentry-read.svc.overdrive.com` endpoint. It was one of the obsolete paths that initially caused certificate/hostname failures.

The important current endpoints are:

```text
POST /chip?c=d:22.0.3&s=0
GET  /chip/clone/code?code=&role=pointer
GET  /chip/clone/code?code=<8-digit-code>&role=pointer
POST /chip/clone
GET  /chip/sync
GET  /card/<cardId>/loan/<loanId>/fulfill/<formatId>
```

Authenticated chip refresh adds `v=<short-chip-id>`:

```text
POST /chip?c=d:22.0.3&s=0&v=<first-8-chars-of-chip-id>
```

The signed ACSM URL returned by fulfillment is normally on:

```text
https://fulfill.contentreserve.com/...
```

The hostname should be taken from the returned URL rather than hard-coded as a trust decision.

## 3. HTTP headers that worked

The tested client presents itself similarly to current Libby Web.

Current tested User-Agent:

```text
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36 Edg/151.0.0.0
```

Default Sentry headers used by the working implementation:

```text
User-Agent: <above>
Accept: application/json
Accept-Encoding: gzip
Referer: https://libbyapp.com/
Origin: https://libbyapp.com
Sec-Fetch-Dest: empty
Sec-Fetch-Mode: cors
Sec-Fetch-Site: same-site
Cache-Control: no-cache
Pragma: no-cache
```

Authenticated calls additionally use:

```text
Authorization: Bearer <identity-jwt>
```

Chip acquisition requires an additional non-obvious header described in section 5.

## 4. Identity model

Libby authentication is centered around an identity JWT returned by `/chip`.

The JWT payload contains a `chip` object. The working implementation needs at least:

```json
{
  "chip": {
    "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}
```

Other claims may include card/account information, but client code should not depend on undocumented claims beyond what is necessary.

Persist the final refreshed identity JWT after successful setup and after a successful fulfillment recovery refresh. Do not log it.

To derive the short chip version value `v`, decode the JWT payload (middle JWT segment, base64url), read `chip.id`, then use the text before the first hyphen. For example:

```text
chip.id = c9aa17a8-8d41-4b55-9cbc-8a88e95d1e0d
v       = c9aa17a8
```

No JWT signature verification is required merely to read this local claim, but the token itself is still supplied back to Libby's server as a bearer credential.

## 5. Critical discovery: Sentry chip "Shib" marker

A major reason ordinary-looking requests failed was that Libby Web applies an obfuscated request transformer to chip acquisition. It rewrites `Accept-Language` to a two-character proof/marker.

This marker is required on `/chip` acquisition/refresh requests. Normal locale strings such as `en-US` are not equivalent.

The algorithm used by the working implementation is:

```python
def chip_accept_language(identity_token="", chip_id=""):
    seed = identity_token or (("xxxxxx" + chip_id) if chip_id else "")
    seed = seed or "cudlkahllcnsjxhbmddl"
    normalized = "".join(ch for ch in seed if "a" <= ch <= "z")[::-1]
    return normalized[4:6]
```

Properties:

- Fresh device with no identity and no chip ID => marker is `bh`.
- Authenticated refresh => marker is derived from the current identity JWT string.
- Only lowercase ASCII `a-z` characters are retained before reversing/slicing.

Regression examples from the working implementation:

```text
chip_accept_language()              -> "bh"
chip_accept_language("abc.def.ghi") -> "ed"
```

Therefore a fresh chip request should look approximately like:

```http
POST /chip?c=d%3A22.0.3&s=0 HTTP/1.1
Host: sentry.libbyapp.com
Accept: application/json
Accept-Language: bh
Origin: https://libbyapp.com
Referer: https://libbyapp.com/
User-Agent: <tested UA>
```

No Authorization header is used for the initial anonymous bootstrap chip.

For an authenticated chip refresh, use the same Shib computation against the active identity token and include the bearer token.

## 6. Correct current authentication/device-copy flow

This was the key behavioral correction. The reliable modern direction is:

**The new client/device displays an 8-digit code. The already trusted Libby device enters that code.**

Do not design the new client around the old assumption that Libby generates a code and the new client consumes it. That older direction may still exist in some UI/API paths, but during testing it produced identities that could sync in some cases yet did not reliably support protected fulfillment.

### Step 1: create an anonymous destination chip

Request:

```text
POST /chip?c=d:22.0.3&s=0
Accept-Language: bh
```

No bearer token.

Save the returned `identity` only as a **pending/bootstrap identity**. Do not yet consider the account authenticated.

Pseudo-code:

```text
bootstrap = POST /chip?c=d:22.0.3&s=0
pending_identity = bootstrap.identity
```

### Step 2: generate a pointer setup code

Using the bootstrap identity as bearer auth:

```text
GET /chip/clone/code?code=&role=pointer
Authorization: Bearer <pending_identity>
```

Expected response contains at least:

```json
{
  "code": "12345678",
  "expiry": 1234567890
}
```

Display the 8-digit code to the user.

### Step 3: trusted Libby device accepts the code

On an already authenticated Libby app/browser:

```text
Menu -> Copy To Another Device -> Enter Setup Code
```

Enter the code displayed by the new client.

The new client does not need access to the trusted device beyond the user entering this code.

### Step 4: poll the pointer code

The new client polls:

```text
GET /chip/clone/code?code=<displayed-code>&role=pointer
Authorization: Bearer <pending_identity>
```

Before acceptance, the response will not have the final fulfilled state.

Success condition:

```json
{
  "result": "fulfilled",
  "blessing": "<opaque-blessing-token>"
}
```

The `blessing` is opaque. Do not decode or transform it.

The Libby web flow polls periodically (we observed approximately 3 seconds). A UI can also let the user press a Verify button and perform one poll per click.

### Step 5: clone using the blessing

Call:

```text
POST /chip/clone
Authorization: Bearer <pending_identity>
Content-Type: application/json; charset=UTF-8
```

Body **must be JSON**, not form encoded:

```json
{"blessing":"<opaque-blessing-token>"}
```

This JSON-vs-form detail was another discovered incompatibility.

If this call returns `403 {"result":"missing_chip"}`, perform the authenticated chip refresh described in section 7 and retry the request once with the refreshed chip identity. Do not treat every 403 as refreshable.

### Step 6: refresh identity after clone

After the blessing clone completes, obtain a refreshed authenticated chip:

```text
POST /chip?c=d:22.0.3&s=0&v=<short-chip-id>
Authorization: Bearer <current identity>
Accept-Language: <Shib marker derived from current identity>
```

Use `identity` from the response as the candidate final account identity.

### Step 7: verify with sync

Set the refreshed identity as bearer and call:

```text
GET /chip/sync
```

A successful authenticated account should return:

```text
result == "synchronized"
```

and a non-empty `cards` array.

Only after this succeeds should the client persist the refreshed identity as its account login.

### Authentication state machine summary

```text
No identity
  |
  | POST /chip?c=d:22.0.3&s=0 + Accept-Language: bh
  v
Bootstrap identity
  |
  | GET /chip/clone/code?code=&role=pointer
  v
Display 8-digit code
  |
  | user enters code on trusted Libby device
  v
Poll GET /chip/clone/code?code=<code>&role=pointer
  |
  | result=fulfilled, blessing=<opaque>
  v
POST /chip/clone JSON {blessing}
  |
  | refresh /chip with c/s/v + Shib
  v
Refreshed identity
  |
  | GET /chip/sync
  | require synchronized + cards
  v
Persist authenticated identity
```

## 7. Generic `missing_chip` recovery rule

Libby distinguishes at least two important 403 bodies observed during this work:

```json
{"result":"missing_chip"}
```

and

```json
{"result":"whoa"}
```

Only `missing_chip` should trigger automatic chip reacquisition.

`whoa` is terminal for that request and should be surfaced rather than put into an infinite refresh loop.

### Authenticated chip refresh

Given an active identity JWT:

1. Decode `chip.id` from the JWT payload.
2. Compute `v` from the first segment of the chip ID.
3. Compute the Shib `Accept-Language` marker from the current JWT string.
4. POST:

```text
/chip?c=d:22.0.3&s=0&v=<short-chip-id>
```

with the current bearer identity.

5. Read `identity` from the response.
6. Retry the original operation once using that returned identity.

For ordinary API calls this can be a generic one-time recovery wrapper.

For **loan fulfillment**, use the stricter same-connection procedure in section 10.

## 8. Scanning account state and loans

Once authenticated, account discovery is simple:

```text
GET /chip/sync
Authorization: Bearer <identity>
```

The synchronized response is the primary source of account state. It contains collections including:

```text
cards
loans
holds
```

The working plugin obtains loans as:

```text
loans = sync_response.get("loans", [])
```

At minimum, an ebook downloader needs these loan fields:

```text
loan.id
loan.cardId
loan.formats[]
loan.type.id
```

Typical format entries have:

```json
{
  "id": "ebook-epub-adobe",
  "isLockedIn": false
}
```

`isLockedIn` can be present when the loan is already committed to a particular reading format.

## 9. Format IDs relevant to ebooks

Known format IDs from the working code:

```text
ebook-epub-adobe   -> Adobe DRM EPUB, fulfillment returns ACSM
ebook-pdf-adobe    -> Adobe DRM PDF, fulfillment returns ACSM
ebook-epub-open    -> DRM-free/open EPUB
ebook-pdf-open     -> DRM-free/open PDF
ebook-kindle       -> Kindle handoff, not a direct ACSM download
ebook-overdrive
ebook-overdrive-provisional
ebook-kobo
```

For an ACSM-focused plugin, the two key values are:

```text
ebook-epub-adobe
ebook-pdf-adobe
```

The current format-selection logic behaves as follows:

1. If any format has `isLockedIn`, use that format if it is supported/downloadable.
2. Otherwise, when configured to prefer open formats, prefer open EPUB.
3. Then Adobe EPUB.
4. Then open PDF if preferred.
5. Then Adobe PDF.
6. Other formats are fallback paths outside the ACSM workflow.

The Calibre implementation has more branches (audiobook, magazine, Kindle, etc.), but a KOReader ebook-only implementation can deliberately scope itself to open EPUB/PDF and Adobe EPUB/PDF.

## 10. Critical discovery: protected ACSM fulfillment must preserve the HTTP connection

This was the other major working breakthrough.

For Adobe DRM fulfillment, a simple independent `GET -> refresh chip -> new GET` sequence was not sufficient. The working implementation performs the initial fulfillment request, chip recovery, and fulfillment retry on the **same persistent HTTPS connection**.

Use one HTTP/1.1 connection to `sentry.libbyapp.com` with keep-alive.

### Initial fulfillment request

For a loan:

```text
loan_id = loan.id
card_id = loan.cardId
format_id = ebook-epub-adobe OR ebook-pdf-adobe
```

Request:

```text
GET /card/<card_id>/loan/<loan_id>/fulfill/<format_id>
Authorization: Bearer <persistent identity>
Connection: keep-alive
Accept: application/json
```

### Case A: immediate HTTP 200

The body is **JSON**, not the ACSM itself.

Proceed to section 11.

### Case B: HTTP 403 + `{"result":"missing_chip"}`

Do not close the HTTPS connection.

On that same connection, POST:

```text
/chip?c=d:22.0.3&s=0&v=<short-chip-id>
```

Headers include:

```text
Authorization: Bearer <original identity>
Connection: keep-alive
Accept-Language: <Shib marker from original identity>
```

No meaningful request body is required.

Expected HTTP 200 JSON contains a new `identity`.

Still on the **same connection**, retry:

```text
GET /card/<card_id>/loan/<loan_id>/fulfill/<format_id>
Authorization: Bearer <new chip identity>
Connection: keep-alive
```

If that returns 200, persist the new chip identity as the current identity and continue to section 11.

If the retry returns 403 `whoa` or anything other than success, treat it as a real failure. Do not keep cycling identities.

### Pseudocode

```text
conn = HTTPSConnection("sentry.libbyapp.com")
try:
    status, body = GET fulfill using primary_identity on conn

    if status == 200:
        return follow_fulfill_href(body)

    if status != 403 or body.result != "missing_chip":
        fail

    new_identity = POST /chip?c=d:22.0.3&s=0&v=<short-id>
                   using primary_identity + Shib
                   on SAME conn

    status, body = GET fulfill using new_identity on SAME conn
    if status != 200:
        fail

    persist(new_identity)
    return follow_fulfill_href(body)
finally:
    conn.close()
```

A port should use an HTTP library that allows connection/session reuse. In Lua/KOReader this likely means deliberately using a keep-alive capable socket/HTTP client rather than convenience helpers that silently construct a fresh connection per request.

## 11. The fulfillment response is JSON containing a signed ACSM URL

The successful protected fulfill response looks conceptually like:

```json
{
  "fulfill": {
    "href": "https://fulfill.contentreserve.com/Book_<...>.acsm?RetailerID=<...>&Expires=<...>&Token=<...>&Signature=<...>"
  }
}
```

Do **not** save this JSON body with an `.acsm` extension. That was an early bug; DeACSM correctly rejected it as an invalid ACSM.

Instead:

1. Parse JSON.
2. Extract `fulfill.href`.
3. Require it to be present.
4. Fetch that URL.
5. Save the returned bytes as `.acsm`.

The signed URL contains temporary authorization material (`Expires`, `Token`, `Signature`), so fetch it promptly and never log or persist it unnecessarily.

The working second-stage request uses:

```text
User-Agent: <tested UA>
Accept: */*
```

It does not need the Libby bearer token.

The body returned by `fulfill.contentreserve.com` is the actual Adobe ACSM XML.

## 12. Open EPUB/PDF behavior (optional for another implementation)

Open-format fulfillment differs from the Adobe flow.

For:

```text
ebook-epub-open
ebook-pdf-open
```

the Libby fulfillment endpoint can respond with an HTTP redirect. The current implementation requests fulfillment without automatically following the first redirect, reads `Location`, then downloads the target.

This is separate from the ACSM workflow and can be implemented later if an initial KOReader plugin only targets Adobe ACSM loans.

## 13. Complete platform-independent workflow

### First-time setup

```text
1. POST /chip?c=d:22.0.3&s=0
   - no bearer
   - Accept-Language: bh
   - store returned identity as pending only

2. GET /chip/clone/code?code=&role=pointer
   - bearer pending identity
   - display returned 8-digit code

3. User enters code on already-authenticated Libby device

4. Poll GET /chip/clone/code?code=<code>&role=pointer
   - bearer pending identity
   - wait for result=fulfilled + blessing

5. POST /chip/clone
   - bearer pending identity
   - JSON body {"blessing":"..."}
   - if missing_chip: one authenticated chip refresh + retry

6. POST /chip?c=d:22.0.3&s=0&v=<short-chip-id>
   - bearer current identity
   - Shib Accept-Language marker
   - get refreshed identity

7. GET /chip/sync
   - bearer refreshed identity
   - require result=synchronized and cards non-empty

8. Persist refreshed identity securely
```

### Normal startup / refresh loans

```text
1. Load persisted identity
2. GET /chip/sync
3. If successful, use response.loans
4. If a normal request returns 403 missing_chip, refresh /chip once and retry
5. Do not auto-refresh for 403 whoa
```

### Download Adobe ebook/PDF loan

```text
1. Choose format:
   ebook-epub-adobe or ebook-pdf-adobe

2. Open one persistent HTTPS connection to sentry.libbyapp.com

3. GET /card/<cardId>/loan/<loanId>/fulfill/<formatId>
   with bearer identity

4. If 403 missing_chip:
   a. POST /chip?c=d:22.0.3&s=0&v=<short-id>
      on same connection, bearer old identity, Shib marker
   b. get new identity
   c. retry fulfill GET on same connection using new identity
   d. persist new identity only after successful fulfillment

5. Parse HTTP 200 body as JSON
6. Extract fulfill.href
7. GET fulfill.href with UA + Accept */*
8. Save returned bytes as <loan>.acsm
9. Hand ACSM to the platform's Adobe fulfillment component, or leave it for external processing
```

## 14. Recommended minimal client abstraction for a new platform

A separate implementation should have a small stateful Libby client with these primitives:

```text
get_chip(authenticated: bool) -> chip response
generate_clone_code() -> {code, expiry}
poll_clone_code(code) -> status/fulfilled+blessing
clone_by_blessing(blessing)
sync() -> account state
get_loans() -> loans[]
fulfill_adobe_loan(card_id, loan_id, format_id) -> ACSM bytes
```

Internal helpers:

```text
default_headers()
decode_chip_id_from_jwt(identity)
short_chip_id(identity)
chip_accept_language(identity)
refresh_chip_once(identity)
parse_fulfill_href(json_body)
download_signed_acsm(url)
```

State to persist:

```text
identity JWT
```

State that should remain temporary:

```text
bootstrap/pending identity during setup
8-digit setup code
blessing token
signed fulfill.href
```

## 15. KOReader/Lua-specific implementation notes

A KOReader plugin does not need Calibre-specific code. The portable requirements are:

- HTTPS with SNI and certificate validation.
- Ability to set custom headers.
- JSON encode/decode.
- Base64url decode of the JWT payload.
- A persistent HTTP/1.1 connection/session for the protected fulfill recovery sequence.
- Secure-ish local storage for the identity token (at minimum do not log it or include it in crash reports).
- UI for first-time setup code display and verification.
- UI/list model for `sync().loans`.
- File writer for ACSM payloads.

For KOReader, a sensible UX could be:

```text
Libby -> Sign in / Copy from another device
      -> Refresh Loans
      -> Loan list
          -> Download ACSM
```

First-time authentication UI:

```text
Generate Code
  -> display 8 digits + expiry
  -> instruction: enter on trusted Libby device
Verify
  -> poll pointer code
  -> clone blessing
  -> refresh identity
  -> sync
```

Do not block the UI thread while polling/networking; KOReader should run network operations asynchronously or yield appropriately.

## 16. Error handling learned during implementation

### TLS hostname mismatch to old service

Symptom:

```text
certificate verify failed: Hostname mismatch for sentry-read.svc.overdrive.com
```

Fix: use `https://sentry.libbyapp.com/`.

### `missing_chip`

Meaning in the working flow: the server expects a current chip acquisition before completing a protected operation.

Action: reacquire `/chip` with `c=d:22.0.3`, `s=0`, `v=<short chip id>`, bearer identity, and Shib marker. Retry once.

### `whoa`

Observed as another 403 result.

Action: terminal. Do not blindly reacquire/retry in a loop.

### Setup code appears accepted in Libby but new device still has no cards

Cause encountered during development: merely calling `/chip/sync` after code acceptance is insufficient.

Required missing steps are:

```text
poll pointer code -> receive blessing -> POST /chip/clone -> refresh /chip -> sync
```

### `/chip/clone` returns `missing_chip`

Important discoveries that made clone work:

- create the bootstrap via modern `?c=d:22.0.3&s=0`, not old `?client=dewey`;
- apply Shib `Accept-Language` on chip acquisition;
- send `POST /chip/clone` body as JSON, not URL-encoded form data;
- allow one `missing_chip` refresh/retry.

### ACSM processor says "ACSM not found or invalid"

Cause encountered: saving the Libby fulfillment JSON wrapper with `.acsm` extension.

Fix: parse `fulfill.href`, fetch it, and save those returned XML bytes as the ACSM.

## 17. Things that should NOT be copied from early failed experiments

Do not build a new client around these approaches:

```text
sentry-read.svc.overdrive.com
POST /chip?client=dewey
assuming sync alone completes a device-copy code
form-encoding the blessing for /chip/clone
using normal locale Accept-Language on /chip
retrying every 403 by acquiring another chip
saving the fulfill endpoint JSON body as .acsm
performing protected fulfillment recovery across unrelated/new HTTP connections
```

## 18. Security/logging requirements

Never log these values:

```text
Authorization bearer JWT
bootstrap identity JWT
refreshed identity JWT
blessing token
full setup-code response if it includes sensitive state
signed fulfill.href
ACSM XML contents
card/user identifiers unless explicitly needed for debugging and redacted
```

If debug request logging exists, redact `Authorization` and query parameters on signed ContentReserve URLs.

A Libby identity token should be treated like a session credential: anyone who obtains a valid one may be able to access the account's Libby state within the token/server validity rules.

## 19. Compatibility/version assumptions

The working flow was validated against Libby Web behavior identified as `d:22.0.3` on 2026-08-13.

The following values may change in future Libby releases and should be centralized as constants:

```text
Sentry base URL
client/version query value d:22.0.3
User-Agent
Shib algorithm
clone-code role semantics
fulfillment response structure
```

If a future implementation suddenly receives `missing_chip`/`whoa` where this flow previously worked, compare current Libby Web requests against these few version-sensitive pieces first.

## 20. Practical acceptance tests for a port

A new implementation should not be considered working until all of these pass:

### Authentication

```text
[ ] Fresh /chip returns identity using Accept-Language bh
[ ] New client generates an 8-digit pointer code
[ ] Existing Libby device accepts the code
[ ] Poll returns result=fulfilled and a blessing
[ ] JSON /chip/clone succeeds (including missing_chip recovery if needed)
[ ] Refreshed /chip returns a new/current identity
[ ] /chip/sync returns synchronized with cards
[ ] Identity persists across application restart
```

### Loan scan

```text
[ ] /chip/sync returns current loans
[ ] loan id, cardId, formats and type can be read
[ ] Adobe EPUB/PDF loans can be identified
```

### ACSM download

```text
[ ] Initial fulfillment request is sent on a reusable HTTPS connection
[ ] missing_chip can be recovered by /chip on the same connection
[ ] fulfillment retry uses the newly returned identity on that same connection
[ ] successful body is parsed as JSON
[ ] fulfill.href is extracted
[ ] signed URL is downloaded immediately
[ ] returned file begins as valid ACSM/XML rather than JSON
[ ] refreshed identity from successful recovery is persisted
```

### Failure behavior

```text
[ ] whoa does not trigger an infinite chip-refresh loop
[ ] missing fulfill.href is treated as an error
[ ] expired setup code can be regenerated cleanly
[ ] no tokens/signed URLs appear in ordinary logs
```

## 21. Reference implementation map

For a future chat/agent that has access to this repository, the authoritative implementation locations are:

```text
calibre-plugin/libby/client.py
  default_headers
  _send_request
  send_request
  _chip_accept_language
  get_chip
  generate_clone_code
  poll_clone_code
  clone_by_blessing
  sync
  get_loans
  get_loan_format
  _urlretrieve
  _download_fulfillment_file
  _fulfill_with_persistent_connection
  fulfill_loan_file

calibre-plugin/config.py
  generate_code_btn_clicked
  verify_generated_setup

tests/libby_client_tests.py
  Shib marker expectations
  fresh/authenticated chip query expectations
  pointer code generation/poll expectations
  JSON blessing clone expectation
  signed ACSM follow-through expectation
  whoa terminal behavior
```

## 22. Bottom line

The current working Libby ebook path is not complicated once the hidden state is reproduced correctly:

```text
modern chip bootstrap + Shib marker
        -> pointer device-copy code
        -> blessing clone
        -> authenticated chip refresh
        -> /chip/sync for loans
        -> same-connection protected fulfill recovery
        -> JSON fulfill.href
        -> actual ContentReserve ACSM
```

The three details most likely to be missed in a clean-room port are:

1. **The new device generates the setup code using `role=pointer`; the trusted existing Libby device enters it.**
2. **`/chip` needs Libby's two-character Shib `Accept-Language` marker, not a normal locale.**
3. **Adobe fulfillment recovery must keep initial fulfill, `/chip` recovery, and retry on the same persistent HTTPS connection.**

Those three points, plus following `fulfill.href` instead of saving the wrapper JSON, are what turned the implementation from account sync only into a working ACSM downloader.
