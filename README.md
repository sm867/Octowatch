# Octowatch

A lightweight, native macOS menu bar app that monitors your GitHub Actions workflow runs in real time.

Built with SwiftUI. No external Swift dependencies. No tracking. No data collection.

> **Requires the [GitHub CLI (`gh`)](https://cli.github.com).** Octowatch does not work without it: all GitHub access goes through `gh`, signed in with `gh auth login`. `gh` is not bundled with the app.

> Octowatch is an independent open-source project and is not affiliated with, endorsed by, or sponsored by GitHub, Inc. "GitHub" is a trademark of GitHub, Inc.


## Features

- **Menu bar status indicator** — see the state of your workflows at a glance
- **Local repo discovery** — pick a folder and Octowatch finds your git repositories (by their `origin` remote) and monitors them
- **Multi-repo monitoring** — default-branch CI status and open PR counts across many repositories, fetched in batched `gh` GraphQL calls
- **Configurable polling** — set your own refresh interval
- **Native notifications** — get notified when workflow runs complete (with distinct sounds for success and failure)
- **Built on the GitHub CLI** — requires `gh`; no tokens to manage — authentication is delegated to the [GitHub CLI](https://cli.github.com); Octowatch never sees or stores a token

## Privacy

Octowatch is fully local. It does not collect, store, or transmit any data to external servers. It talks to GitHub only by running `gh` on your behalf, with the account you are signed in with there, and never reads or stores your credentials. Preferences are saved locally via UserDefaults. There is no analytics, no telemetry, no phone-home behavior of any kind.

## Requirements

- macOS 14.0 or later
- Swift 6.0+ (to build from source)
- **[GitHub CLI](https://cli.github.com) (`gh`) — mandatory.** Install with `brew install gh` and sign in with `gh auth login`. The app looks for it in `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`. If you use several accounts, Octowatch uses the one currently active in `gh` (`gh auth switch`)

## Installation

### Build from source

Clone the repository and use the provided Makefile:

```bash
git clone https://github.com/sm867/Octowatch.git
cd Octowatch
make run
```

This builds a release `.app` bundle and launches it. The app lives in your menu bar — there is no Dock icon.

### Download a release

Pushing a tag like `v1.0.0` triggers a GitHub Actions workflow that builds the app and attaches `Octowatch-<tag>.zip` (with a SHA-256 checksum) to a GitHub release. See [unsigned builds](#note-on-unsigned-builds) if macOS blocks it.

### Other make targets

```bash
make build    # Debug build
make release  # Release build
make bundle   # Build .app bundle (release) without launching
make open     # Launch an existing bundle (no rebuild)
make clean    # Remove build artifacts and .app bundle
```

## How it uses `gh`

Octowatch runs the `gh` binary installed on your machine, as you, with the account that is active in `gh`. It only reads data: `gh api user` and read-only `gh api graphql` queries for the repositories you selected (default-branch CI status, open PR count). It never writes to GitHub, never reads `gh`'s stored credentials, and sends nothing anywhere else. `gh` is a separate project by GitHub, licensed under MIT; it is not part of this repository.

## Usage

1. Launch Octowatch — it appears in your menu bar
2. Make sure `gh` is installed and signed in (`gh auth login`); the app tells you if it is not
3. Choose the folder that contains your local clones and select the repositories you want to monitor
4. Octowatch will poll GitHub Actions and update the menu bar indicator in real time

## Tech Stack

| | |
|---|---|
| **Language** | Swift 6.0 (strict concurrency) |
| **UI** | SwiftUI |
| **Architecture** | MVVM |
| **Dependencies** | None — stdlib, Foundation, SwiftUI, UserNotifications only (runtime: `gh`) |
| **Min. deployment** | macOS 14.0 |

## Note on unsigned builds

The app is not signed with a paid Apple Developer ID. If macOS blocks a downloaded build, remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine Octowatch.app
```

Building from source with `make run` avoids this.

## Authors

- [Hugo Bourget](https://github.com/hbourget) — original author of [Octowatch](https://github.com/hbourget/Octowatch)
- [sm867](https://github.com/sm867) — this version: GitHub CLI integration instead of a personal access token, local repository discovery


## License

This project is licensed under the [MIT License](LICENSE). Copyright (c) 2026 Hugo Bourget and sm867.
