# Libby Dashboard for KOReader

Libby Dashboard is a self-contained KOReader plugin for browsing and reading supported loans from libraries linked to a Libby account. It brings your Libby loans, holds, magazine subscriptions, and audiobook shelf directly to the e-reader instead of requiring a separate computer for normal borrowing and fulfillment.

**Libby Dashboard focuses on your current loans, holds, and subscribed magazines. It cannot browse or search your library catalog or place new holds, but a hold that becomes available can be borrowed directly from the plugin. Other new titles must still be found and borrowed through the official Libby application.**

Current plugin version: **0.2.8.1**

## Installation

1. Download the latest `libby-dashboard.koplugin.zip` from GitHub Releases.
2. Extract the ZIP.
3. Copy the entire `libby-dashboard.koplugin` folder to KOReader's `plugins` folder.
4. Restart KOReader.
5. Open **Libby Dashboard** from KOReader's **Tools** menu. Use **Settings → Accounts** to configure **Libby Account** and **ByteBooks / Adobe Authorization**.

After the initial installation, future releases can be installed directly from **Settings → General → Check for Updates**.

## Tested devices

Libby Dashboard has been successfully tested across touch and non-touch KOReader devices, including:

- Boox Go 7 Gen 2
- Kindle Paperwhite Signature Edition (12th Gen)
- Kindle 4th Generation non-touch — including D-pad navigation, Settings, account-backup restore, Libby library restore, and ByteBooks authorization restore
- Kobo Clara BW
- Samsung Galaxy S24-Ultra

## Screenshots

### Library Browser

<p align="center">
  <img src="assets/01%20-%20All_Libraries_Grid.png" alt="All Libraries grid view" width="350" height="750">
  <img src="assets/02%20-%20All_Libraries_List.png" alt="All Libraries list view" width="350" height="750">
</p>
<p align="center">
  <img src="assets/03%20-%20All_Libraries_Grid_Holds.png" alt="All Libraries holds grid view" width="350" height="750">
  <img src="assets/04%20-%20All_Libraries_List_Holds.png" alt="All Libraries holds list view" width="350" height="750">
</p>
<p align="center">
  <img src="assets/05%20-%20Single_Library_Grid.png" alt="Single library grid view" width="350" height="750">
  <img src="assets/06%20-%20Single_Library_List.png" alt="Single library list view" width="350" height="750">
</p>

### Media Racks

<p align="center">
  <img src="assets/07%20-%20Audiobook_Rack_Grid.png" alt="Audiobook Rack grid view" width="350" height="750">
  <img src="assets/08%20-%20Audiobook_Rack_List.png" alt="Audiobook Rack list view" width="350" height="750">
</p>
<p align="center">
  <img src="assets/09%20-%20Magazine_Rack_Grid.png" alt="Magazine Rack grid view" width="350" height="750">
  <img src="assets/10%20-%20Magazine_Rack_List.png" alt="Magazine Rack list view" width="350" height="750">
</p>

### Settings

<p align="center">
  <img src="assets/11%20-%20Settings_General.png" alt="General settings" width="350" height="750">
  <img src="assets/12%20-%20settings_Accounts.png" alt="Accounts settings" width="350" height="750">
</p>
<p align="center">
  <img src="assets/13%20-%20Settings_Downloads.png" alt="Download settings" width="350" height="750">
  <img src="assets/14%20-%20Settings_Shelves_Setup.png" alt="Library and shelves settings" width="350" height="750">
</p>
<p align="center">
  <img src="assets/15%20-%20Settings_About.png" alt="About settings" width="350" height="750">
</p>

## What it does

- Authenticates with Libby using Libby's device setup-code flow.
- Opens directly into the full **Library Browser**, with configurable **Grid** and **List** views.
- Displays every linked library individually plus a combined **All Libraries** view, and remembers the last library/rack and Grid/List mode used.
- Displays current holds with queue/wait/suspension status and direct borrowing when a hold becomes available.
- Provides dedicated **Audiobooks** and **Magazine Rack** views, grouped by source library when multiple library cards contribute items.
- Builds Magazine Rack from both checked-out magazine issues and Libby **Notify Me** subscriptions, including subscription-only current issues.
- Retrieves covers for subscription-only magazine issues and marks a subscribed magazine **NEW ISSUE** when Libby delivers a newer issue.
- Shows magazine frequency plus edition/publication metadata, while audiobooks use **Listen on Libby** for Libby-only playback.
- Keeps local **Book Notes** attached to a title across its hold, borrowed, downloaded, and Extended Loan lifecycle.
- Shows title details including author or magazine edition, series information, format, lending library, and remaining loan time when available.
- Downloads supported EPUB loans and opens the resulting book directly in KOReader. PDF fulfillment is implemented but has not yet been validated with a real Libby PDF loan.
- Keeps unsupported reading formats such as MediaDo manga/comics visible with useful cover and metadata information.
- Returns active loans to Libby early from the title detail panel, with confirmation before the return is submitted.
- Supports hardware D-pad navigation on non-touch devices, including the root browser, header actions, title details, and Settings.
- Supports Adobe/ByteBooks authorization, including ByteBooks username/password authorization and anonymous Adobe authorization.
- Creates password-protected account backups containing the Libby authorization and Adobe/ByteBooks registration state for portable restore to another device.
- Registers as an ACSM handler, so supported external `.acsm` files can also be fulfilled and opened through the plugin.
- Caches the Libby library snapshot and covers, including Magazine Rack subscription covers, for useful offline browsing.
- Tracks downloaded loans so the local shelf can follow the state of the Libby loan.

## How book loans are handled

Libby Dashboard treats downloaded books as library loans rather than permanent entries in its managed library. It records successfully downloaded loans and compares those records with the current Libby loan shelf and the loan expiration information.

When a managed loan expires or is returned early and disappears from the Libby account, Libby Dashboard removes the downloaded book from its managed book location. Empty folders created by the configured storage path are cleaned up as well.

KOReader reading history is handled separately from the borrowed book file. Before a managed book is removed, its `.sdr` sidecar directory is moved into Libby Dashboard's private history storage. That preserves KOReader reading progress, annotations, highlights, and other document settings. If the same title is borrowed and downloaded again later, the saved sidecar is restored beside the new book so KOReader can continue with the previous reading state.

A book that a user manually moves outside the location tracked by Libby Dashboard is no longer under the plugin's file-management control.

## Libby and Adobe/ByteBooks accounts

Libby authentication and Adobe/ByteBooks authorization are intentionally separate. Resetting the Libby account does not silently reset Adobe/ByteBooks authorization.

ByteBooks account authorization is the preferred method because the same account can authorize multiple supported devices. Anonymous Adobe authorization is also supported.

If Libby Dashboard detects an existing anonymous Adobe authorization created by the KOReader `acsm.koplugin`, it will use that authorization initially rather than creating another one. The user can still replace it at any time by generating a new anonymous authorization or, preferably, signing in with a ByteBooks account.

Authorization and account data can be backed up and restored when needed. Backups contain private account credentials and are encrypted using the password you provide. Store both the backup file and its password securely.

## Storage

Plugin settings, cached state, covers, and preserved reading history are kept under KOReader's settings directory in the dedicated `libby-dashboard` folder.

The default downloaded-book layout is:

```text
HOME/Libby_Loans/<author:first>/<series>/<series_index> - <title>.<ext>
```

`<author:first>` refers to the first author when a book has multiple authors.

## Development

The repository contains the installable KOReader plugin in `libby-dashboard.koplugin/` together with Lua protocol/core code and tests used during development. The compatibility target is Lua 5.1 / LuaJIT as used by KOReader.

The implementation has also benefited from selected ideas and functions from the Libby calibre plugin projects and `acsm.koplugin`. Portions derived from `acsm.koplugin` retain the original MIT license notice in `libby-dashboard.koplugin/LICENSE-acsm.koplugin`. See the in-plugin Credits page for project links and acknowledgements.

## AI-assisted development disclaimer

Libby Dashboard has been put together with assistance from OpenAI's ChatGPT. AI assistance has been used while designing, implementing, debugging, reviewing, and testing portions of the plugin.

If you do not want to use software developed with AI assistance, please do not install Libby Dashboard. The source is available for review so you can make your own decision before running it on your device.

## Links & Support

- [Techy Notes](https://techy-notes.com) — blog, projects, notes, and guides.
- [Jadehawk on YouTube](https://youtube.com/@jadehawk) — videos and project content.
- [Buy Me a Coffee](https://buymeacoffee.com/jadehawk) — if you would like to support my projects.

## Project status

Libby Dashboard is an independent personal project. It is not affiliated with or endorsed by Libby, OverDrive, Adobe, ByteBooks, KOReader, or the projects acknowledged in the Credits page.
