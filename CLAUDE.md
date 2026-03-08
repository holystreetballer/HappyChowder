# CLAUDE.md

Instructions for Claude Code when working on the HappyChowder project.

## Project Overview

HappyChowder is a native iOS app (Swift/SwiftUI, iOS 17+) that combines:
- **Happy** — Encrypted relay infrastructure (Socket.IO + E2E encryption) for remote Claude Code control
- **Chowder** — Live Activity UI (Lock Screen + Dynamic Island) for real-time agent status

The app lets users control Claude Code sessions on their Mac from their iPhone with persistent Live Activities.

## Build System

- **XcodeGen** generates `HappyChowder.xcodeproj` from `HappyChowder/project.yml`
- After adding/removing/renaming Swift files, run `cd HappyChowder && xcodegen generate`
- SPM dependencies: `socket.io-client-swift` (v16.1.1), `swift-sodium` (v0.9.2)
- Deployment target: iOS 17.0
- Swift version: 6.0

## Project Structure

```
HappyChowder/                   # Git root
├── HappyChowder/               # XcodeGen project root
│   ├── project.yml              # XcodeGen config — edit this, not the .xcodeproj
│   ├── HappyChowder/            # Main app target sources
│   │   ├── HappyChowderApp.swift
│   │   ├── Auth/                # AuthManager, AuthView, QRScannerView
│   │   ├── Models/              # Data models
│   │   │   ├── SessionProtocol.swift   # Wire protocol types (SessionEnvelope, events, AgentState, machines)
│   │   │   ├── AgentActivity.swift     # ToolCategory, ActivityStep, AgentActivity
│   │   │   ├── Message.swift           # Chat message model
│   │   │   ├── ConnectionConfig.swift  # Server URL + Keychain-backed credentials
│   │   │   └── SharedStorage.swift     # App Group container for widget
│   │   ├── Services/
│   │   │   ├── HappySessionService.swift  # Core transport: Socket.IO + HTTP + encryption
│   │   │   ├── EncryptionService.swift    # HKDF + NaCl sealed box + AES-256-GCM
│   │   │   ├── LiveActivityManager.swift  # ActivityKit lifecycle management
│   │   │   ├── NotificationManager.swift  # Local push notifications
│   │   │   ├── TaskSummaryService.swift   # Apple Intelligence (FoundationModels) integration
│   │   │   ├── KeychainService.swift      # Keychain CRUD
│   │   │   └── LocalStorage.swift         # File-based persistence
│   │   ├── ViewModels/
│   │   │   └── ChatViewModel.swift        # Central state management (~600 lines)
│   │   └── Views/
│   │       ├── ChatView.swift             # Main chat screen
│   │       ├── ChatHeaderView.swift       # Header with status, cost badge, nav buttons
│   │       ├── SessionsListView.swift     # Multi-session picker
│   │       ├── PermissionRequestView.swift # Tool approval modal
│   │       ├── CostTrackingView.swift     # Cost dashboard
│   │       ├── MachinesView.swift         # Machine status list
│   │       ├── QuickReplyBar.swift        # Quick action buttons
│   │       ├── SessionMetadataView.swift  # Session info sheet
│   │       ├── SettingsView.swift         # Settings + glass components
│   │       ├── ThinkingShimmerView.swift  # Animated thinking indicator
│   │       ├── ActivityStepRow.swift      # Inline completed step row
│   │       ├── AgentActivityCard.swift    # Activity detail sheet
│   │       ├── MessageBubbleView.swift    # Chat bubble with markdown
│   │       └── MarkdownContentView.swift  # Custom markdown renderer
│   ├── Shared/
│   │   └── HappyChowderActivityAttributes.swift  # ActivityKit attributes (shared with widget)
│   └── HappyChowderWidget/
│       ├── HappyChowderWidgetBundle.swift
│       └── HappyChowderLiveActivity.swift  # Lock Screen + Dynamic Island UI
```

## Key Architectural Patterns

### Delegate Pattern
`HappySessionService` communicates with `ChatViewModel` via `HappySessionServiceDelegate`. New delegate methods have default empty implementations so they're optional.

### Encryption Pipeline
Master secret → HKDF → NaCl keypair → decrypt per-session AES key → AES-256-GCM for messages. All in `EncryptionService.swift`. Session keys cached by session ID.

### Live Activity State
`ChatViewModel` maintains a 3-slot intent stack (bottom text, yellow card, grey card) that feeds `LiveActivityManager`. Updates are debounced at 1 second. Past-tense conversion via `TaskSummaryService` (Apple Intelligence).

### Socket.IO Events
- `update` events are persistent (sequenced): `new-message`, `update-session`, `update-machine`
- `ephemeral` events are transient: `activity`, `machine-activity`, `usage`

### Permission Flow
1. Server sends `update-session` with encrypted `agentState` containing `requests`
2. `HappySessionService` decrypts and calls `serviceDidReceivePermissionRequests`
3. `ChatViewModel` shows `PermissionRequestView` modal
4. User approves/denies → `respondToPermission()` → Socket.IO `update-state` emit

## Coding Conventions

- Use `@Observable` (iOS 17 Observation framework), not `ObservableObject`
- Views use `@State private var viewModel = ChatViewModel()` pattern
- All UI work dispatched to main queue from service callbacks
- Haptic feedback via `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`
- Glass design system: `GlassCard`, `GlassIcon`, `GlassTextField`, `GlassSaveButton` in SettingsView.swift
- Debug logging via buffered `log()` method in ChatViewModel (flushes every 0.5s)

## Important Notes

- **SourceKit false positives**: When analyzing outside Xcode, SourceKit reports errors like "No such module 'UIKit'" or "Cannot find type" — these resolve when building against the iOS SDK
- **`#if canImport(FoundationModels)`**: TaskSummaryService uses Apple Intelligence, with a stub fallback for older SDKs
- **App Group**: `group.com.happychowder.app` shared between main app and widget extension
- **Keychain service**: `com.happychowder.app` — stores auth token and master secret
- **No app icon**: The `AppIcon.appiconset` is currently a placeholder

## Source Repos (Reference)

The `happy-repo/` and `chowder-repo/` directories are gitignored reference clones:
- Happy protocol: `happy-repo/packages/happy-wire/src/sessionProtocol.ts`
- Happy encryption: `happy-repo/packages/happy-app/sources/sync/encryption/`
- Happy socket: `happy-repo/packages/happy-app/sources/sync/apiSocket.ts`
- Chowder Live Activity: `chowder-repo/Chowder/ChowderActivityWidget/ChowderLiveActivity.swift`
- Chowder ChatService: `chowder-repo/Chowder/Chowder/Services/ChatService.swift`
