# Loft

I wanted a simple tool to move the folders and files that eat my MacBook's disk onto my NAS in one click. This app does that, and it also shows where your storage went.

A native SwiftUI app for macOS 14+ (Apple Silicon).

## What it does

- **Move to NAS**: browse your Mac (every folder shows its size), add items to a copy list, press Copy. Files are copied to a folder on your NAS share and checked by SHA-256 read-back. Optionally move the originals to the Trash, or delete them, only after the copy is verified.
- **Overview**: a free-space ring, "Safe to clear" (caches, logs, build files) and "Worth a look" (Downloads, simulators, archives), and a treemap of your home folder.
- **Biggest**: the largest files and folders on your Mac. Results appear while the scan runs and are remembered between launches.
- **Duplicates**: finds identical big files and keeps one copy.
- Finder-style selection (Cmd/Shift-click), arrow keys, Return to open, Space to Quick Look, Delete to trash.
- Light and dark mode.

## Built from

| Tool | Used for | License |
|---|---|---|
| [Mole](https://github.com/tw93/Mole) | deep cleaning (bundled, opened from the Overview tab) | MIT |
| [fclones](https://github.com/pkolaczk/fclones) | duplicate finding (bundled arm64 binary) | MIT |
| Bricolage Grotesque, Schibsted Grotesk, Spline Sans Mono | fonts | SIL OFL 1.1 |
| SwiftUI, CryptoKit, QuickLook | app, hashing, previews | Apple frameworks |

Licenses are in `Vendor/licenses` and inside the app (Licenses button).

## Install

Download `Loft.zip` from [Releases](../../releases), unzip, and move the app to Applications. The app is not notarized, so on first launch right-click it and choose Open.

Connect your NAS in Finder first (Go > Connect to Server, `smb://your-nas`). The app finds mounted SMB shares from your NAS. The default address is `192.168.50.220`; set yours with:

```bash
defaults write com.dhananjay.loft nasHost your-nas-ip-or-name
```

## Build

```bash
brew install xcodegen
./scripts/fetch-tools.sh   # copies Mole from Homebrew into Vendor/tools
xcodegen generate
xcodebuild -project Loft.xcodeproj -scheme Loft -configuration Release build
```

## Safety

Deletes only touch files inside your home folder. Originals are removed only after the NAS copy is verified, and Move to Trash is the default. Tested with a local harness and on a Mac; a real-NAS copy has had limited testing, so try it on files you can spare first.

## License

MIT. Bundled tools keep their own licenses.
