# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Octowatch is a native macOS menu bar application (SwiftUI) that monitors GitHub Actions workflow runs across multiple repositories. It talks to GitHub exclusively through the `gh` CLI (no tokens handled by the app). Repositories are discovered by scanning a user-chosen local folder for git repos with a GitHub `origin`, then status is polled at configurable intervals via batched `gh api graphql` calls.

## Build & Run Commands

A `Makefile` is provided for convenience:

```bash
make build    # Debug build
make release  # Release build
make bundle   # Build .app bundle (release)
make run      # Build bundle and launch the app
make open     # Launch existing bundle (no rebuild)
make clean    # Remove build artifacts and .app bundle
```

There are no tests, linter, or formatter configured in this project.

## Architecture

**MVVM pattern** with a single `WorkflowViewModel` (@Observable, @MainActor) as the central state manager.

### Data Flow

```
OctowatchApp (@main)
└── MenuBarExtra
    ├── MenuBarLabel ← reads aggregateStatus
    └── MainPopoverView ← owns WorkflowViewModel
        ├── GHSetupView (gh missing / not signed in)
        ├── SettingsView (polling interval, repo selection)
        └── Authenticated content (header, run list, footer)
```

### Key Components

- **WorkflowViewModel** (`ViewModels/WorkflowViewModel.swift`): Single source of truth. Manages gh auth state, polling loop, notification triggers, and persisted settings (UserDefaults: polling interval, sound, selected repos, repos folder).
- **GHCLIClient** (`Services/GHCLIClient.swift`): Swift `actor` that runs `gh` via `Process` (fixed PATH, timeout watchdog, exit code 4 = not authenticated) and batches repo queries into GraphQL calls.
- **LocalRepoScanner** (`Services/LocalRepoScanner.swift`): Walks the chosen folder to find git repos and parses their `origin` remote.
- **NotificationService** (`Services/NotificationService.swift`): Sends macOS notifications when workflow runs complete.
- **Models** (`Models/WorkflowRun.swift`): `Repository`, `RepoSummary`, `GitHubUser` and `AggregateStatus`.

### Key Patterns

- Swift 6.0 strict concurrency (`actor` for API client, `@MainActor` for ViewModel, `Sendable` models)
- Never handle credentials; always go through `gh`
- `make build` (not bare `swift build`) works around the Command Line Tools SDK macro issue
- Zero external dependencies — only Swift stdlib, Foundation, SwiftUI, and UserNotifications
- `LSUIElement: true` in Info.plist (menu bar only, no dock icon)
- macOS 14.0+ minimum deployment target
