# Libby Dashboard for KOReader

Libby Dashboard is a self-contained KOReader plugin for browsing and reading supported loans from libraries linked to a Libby account. It brings the loan shelf directly to the e-reader instead of requiring a separate computer for normal borrowing and fulfillment.

**Libby Dashboard is a dashboard for loans you have already borrowed. It cannot browse or search your library catalog and cannot borrow new titles. New loans must be borrowed through the official Libby application before they will appear in Libby Dashboard.**

Current plugin version: **0.2.6**

## Installation

1. Download the latest `libby-dashboard.koplugin.zip` from GitHub Releases.
2. Extract the ZIP.
3. Copy the entire `libby-dashboard.koplugin` folder to KOReader's `plugins` folder.
4. Restart KOReader.
5. Open **Libby Dashboard** from KOReader's **Tools** menu and complete the required setup under **Authentication**: **Libby Setup** and **Adobe/ByteBooks Setup**.

After the initial installation, future releases can be installed directly from **Libby Dashboard Settings → Check for Updates**.

## Tested devices

Libby Dashboard has been successfully tested for Libby login, ByteBooks sign-in, and book downloads on:

- Boox Go 7 Gen 2
- Kindle Paperwhite Signature Edition (12th Gen)
- Kobo Clara BW
- Samsung Galaxy S24-Ultra

## Screenshots

<p align="center">
  <img src="assets/01-Main_UI.png" alt="Libby Dashboard main UI" width="350" height="750">
  <img src="assets/02-Comic-Manga.png" alt="Libby Dashboard comic and manga loan" width="350" height="750">
</p>
<p align="center">
  <img src="assets/03-Audiobook.png" alt="Libby Dashboard audiobook loan" width="350" height="750">
  <img src="assets/04-DownloadBook01.png" alt="Download book flow" width="350" height="750">
</p>
<p align="center">
  <img src="assets/04-DownloadBook02.png" alt="Download book confirmation" width="350" height="750">
  <img src="assets/04-DownloadBook03.png" alt="Downloaded book ready to open" width="350" height="750">
</p>
<p align="center">
  <img src="assets/05-ReturnBook01.png" alt="Return book action" width="350" height="750">
  <img src="assets/05-ReturnBook02.png" alt="Return book confirmation" width="350" height="750">
</p>
<p align="center">
  <img src="assets/06-Settings01.png" alt="Libby Dashboard settings" width="350" height="750">
  <img src="assets/06-Settings02.png" alt="Libby Dashboard settings" width="350" height="750">
</p>
<p align="center">
  <img src="assets/06-Settings03.png" alt="Libby Dashboard settings" width="350" height="750">
  <img src="assets/06-Settings04.png" alt="Libby Dashboard settings" width="350" height="750">
</p>
<p align="center">
  <img src="assets/06-Settings05.png" alt="Libby Dashboard settings" width="350" height="750">
  <img src="assets/06-Settings06.png" alt="Libby Dashboard settings" width="350" height="750">
</p>
<p align="center">
  <img src="assets/06-Settings07.png" alt="Libby Dashboard settings" width="350" height="750">
</p>

## What it does

- Authenticates with Libby using Libby's device setup-code flow.
- Displays all linked library cards, plus a combined **All** shelf.
- Presents loans in a configurable cover grid with a responsive selected-book details panel and library tabs.
- Shows title, author, series information, format, lending library, and remaining loan time when available.
- Downloads supported EPUB loans and opens the resulting book directly in KOReader. PDF fulfillment is implemented but has not yet been validated with a real Libby PDF loan.
- Identifies unsupported loan types such as audiobooks, magazines, and MediaDo manga/comics so they can still appear on the shelf with useful cover and metadata information.
- Returns active loans to Libby early from the selected-book panel, with confirmation before the return is submitted.
- Supports Adobe/ByteBooks authorization, including ByteBooks username/password authorization and anonymous Adobe authorization.
- Creates password-protected account backups containing the Libby authorization and Adobe/ByteBooks registration state for portable restore to another device.
- Registers as an ACSM handler, so supported external `.acsm` files can also be fulfilled and opened through the plugin.
- Caches the Libby library snapshot and covers for useful offline browsing.
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
HOME/Libby_Books/<author:first>/<series>/<title>.<ext>
```
```text
<author:first> Refers to the First Author incase of Multi-Author book.
```

## Development

The repository contains the installable KOReader plugin in `libby-dashboard.koplugin/` together with Lua protocol/core code and tests used during development. The compatibility target is Lua 5.1 / LuaJIT as used by KOReader.

The implementation has also benefited from selected ideas and functions from the Libby calibre plugin projects, `acsm.koplugin`, and UI/layout ideas from `bookshelf.koplugin`. Portions derived from `acsm.koplugin` retain the original MIT license notice in `libby-dashboard.koplugin/LICENSE-acsm.koplugin`. See the in-plugin Credits page for project links and acknowledgements.

## AI-assisted development disclaimer

Libby Dashboard has been put together with assistance from OpenAI's ChatGPT. AI assistance has been used while designing, implementing, debugging, reviewing, and testing portions of the plugin.

If you do not want to use software developed with AI assistance, please do not install Libby Dashboard. The source is available for review so you can make your own decision before running it on your device.

## Links & Support

- [Techy Notes](https://techy-notes.com) — blog, projects, notes, and guides.
- [Jadehawk on YouTube](https://youtube.com/@jadehawk) — videos and project content.
- [Buy Me a Coffee](https://buymeacoffee.com/jadehawk) — if you would like to support my projects.

## Project status

Libby Dashboard is an independent personal project. It is not affiliated with or endorsed by Libby, OverDrive, Adobe, ByteBooks, KOReader, or the projects acknowledged in the Credits page.
