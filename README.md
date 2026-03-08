# HappyChowder

A native iOS app for controlling [Claude Code](https://claude.ai/claude-code) sessions remotely from your iPhone, with persistent Live Activities showing real-time progress on your Lock Screen and Dynamic Island.

Built by combining [Happy](https://github.com/slopus/happy) (encrypted relay infrastructure) with [Chowder](https://github.com/newmaterialco/chowder-iOS) (Live Activity UI).

## Features

### Core
- **Remote Claude Code control** — Send messages to Claude Code sessions running on your Mac from your iPhone
- **End-to-end encryption** — All communication encrypted with NaCl sealed box + AES-256-GCM, matching Happy's wire protocol
- **QR code pairing** — Scan a QR code from `happy pair` to connect instantly

### Live Activities
- **Lock Screen banner** — Persistent 160pt banner showing current task, stacked intent cards with depth effect, cost badge, and live timer
- **Dynamic Island** — Compact, expanded, and minimal variants with real-time status
- **Thinking shimmer** — Animated shimmer with pulsing dot while Claude thinks
- **Inline activity steps** — Completed tool calls shown inline in the chat with haptic feedback

### Multi-Session & Machine Management
- **Session list** — Browse and switch between Claude Code sessions, grouped by machine
- **Machine status** — Monitor connected machines with online/offline indicators and daemon info
- **Session metadata** — View working directory, host, OS, Claude version, and available tools

### Permission Handling
- **Remote tool approval** — Approve or deny Claude's tool calls (file writes, bash commands, etc.) directly from your phone
- **Push notifications** — Get alerted when Claude needs permission, even when the app is backgrounded
- **Haptic feedback** — Warning haptic when a permission request arrives

### Cost Tracking
- **Per-session costs** — Track token usage and dollar costs per session
- **Live Activity integration** — Cost badge updates in real-time on your Lock Screen
- **Cost dashboard** — Overview of total spend with per-session breakdown

### Chat
- **Markdown rendering** — Code blocks, headings, lists, blockquotes, inline formatting
- **Quick reply buttons** — Continue, Yes, No, Explain, Undo, Status shortcuts
- **Stop button** — Interrupt a running agent turn mid-execution
- **Message pagination** — Lazy loading with "load earlier messages" support

## Requirements

- iOS 17.0+
- Xcode 16.0+
- A running [Happy](https://github.com/slopus/happy) server with Claude Code CLI connected

## Setup

### 1. Install Happy

Follow the [Happy setup guide](https://github.com/slopus/happy) to:
- Deploy the Happy server
- Install the Happy CLI on your Mac
- Start a Claude Code session with `happy start`

### 2. Build the iOS App

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Generate the Xcode project
cd HappyChowder
xcodegen generate

# Open in Xcode
open HappyChowder.xcodeproj
```

Xcode will resolve the SPM dependencies automatically:
- [socket.io-client-swift](https://github.com/socketio/socket.io-client-swift) v16.1.1
- [swift-sodium](https://github.com/nicklama/swift-sodium) v0.9.2

### 3. Pair Your Device

Run `happy pair` on your Mac to generate a QR code, then scan it in the app. The QR code contains:
- Server URL
- Authentication token (JWT)
- Master secret (32-byte base64)

Or enter the connection details manually in Settings.

## Architecture

```
HappyChowder/
├── HappyChowder/              # Main app target
│   ├── Auth/                   # QR pairing, AuthManager
│   ├── Models/                 # SessionProtocol, AgentActivity, Message
│   ├── Services/               # HappySessionService, EncryptionService,
│   │                           # LiveActivityManager, NotificationManager
│   ├── ViewModels/             # ChatViewModel (central glue)
│   └── Views/                  # ChatView, SessionsListView, PermissionRequestView,
│                               # CostTrackingView, MachinesView, QuickReplyBar, etc.
├── Shared/                     # HappyChowderActivityAttributes (app + widget)
├── HappyChowderWidget/         # Widget extension (Live Activity)
└── project.yml                 # XcodeGen project definition
```

### Transport Layer

```
Claude Code (Mac)
    ↓ JSONL stream
Happy CLI → SessionEnvelope → encrypt → POST /v3/sessions/:id/messages
    ↓
Happy Server (Fastify + Socket.IO + PostgreSQL)
    ↓ Socket.IO "update" event
HappyChowder iOS App
    ↓ decrypt → parse SessionEnvelope → delegate callbacks
ChatViewModel → UI updates + Live Activity
```

### Encryption Flow

1. Master secret (32 bytes from QR) → HKDF → X25519 keypair
2. Per-session AES key decrypted from NaCl sealed box (version byte 0 + anonymous box)
3. Messages encrypted/decrypted with AES-256-GCM (12-byte nonce + ciphertext + 16-byte tag)

### Session Protocol Events

| Event | Description |
|-------|-------------|
| `text` | Text delta (with optional `thinking: true`) |
| `tool-call-start` | Tool invocation with name, args, title |
| `tool-call-end` | Tool completion |
| `turn-start` / `turn-end` | Agent turn lifecycle |
| `start` / `stop` | Session lifecycle |
| `service` | Service messages |
| `file` | File references |

## License

MIT
