# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Speakin is a macOS menu bar application that provides push-to-talk voice transcription using WhisperKit. Press and hold the right Option key to record audio, which is then transcribed locally using Apple's on-device ML and inserted at the cursor position.

## Build Commands

```bash
# Build the project
swift build

# Run the application
swift run

# Build with Xcode
open Speakin.xcodeproj
# Then: Product > Build (⌘B)

# Run from Xcode build
.build/debug/Speakin

# Clean build artifacts
swift package clean
```

Note: This project uses Swift Package Manager with an Xcode project wrapper. The Package.swift defines dependencies, but you should use Xcode for development.

## Architecture

### Application Flow

1. **Initialization** (SpeakinApp.swift → AppDelegate):
   - Check/request permissions (microphone + accessibility)
   - Download WhisperKit model if not present (first launch only)
   - Initialize TranscriptionEngine with downloaded model
   - Start HotkeyMonitor for right Option key events

2. **Recording Flow** (Key Down → Key Up):
   - `handleKeyDown()` → AudioRecorder.startRecording()
   - Audio recorded at 48kHz native → converted to 16kHz for Whisper
   - `handleKeyUp()` → AudioRecorder.stopRecording() (async completion)
   - TranscriptionEngine.transcribe() processes audio
   - TextInserter injects result at cursor position

3. **State Management**:
   - AppState.shared manages UI state (idle/listening/processing/success/error)
   - IconStateManager observes AppState and updates menu bar icon
   - State transitions trigger visual feedback (animated dots, checkmarks, errors)

### Core Components

**AudioRecorder.swift** - Real-time audio capture with buffer batching:
- Uses AVAudioEngine with installTap on input node
- Two-queue architecture prevents Core Audio thread blocking:
  - `processingQueue`: Fast buffer conversion/accumulation (off audio thread)
  - `writeQueue`: Disk I/O operations (completely decoupled)
- AudioBufferAccumulator batches 10 buffers (~2.5s) before writing
- This prevents kAudioUnitErr_RenderTimeout (-10877) by reducing I/O 90%
- Async completion callbacks for non-blocking shutdown

**TranscriptionEngine.swift** - WhisperKit wrapper:
- Singleton that initializes WhisperKit on first launch
- Two initialization paths:
  - Path A: Model exists → load from disk (fast)
  - Path B: No model → download openai_whisper-small to ~/Library/Application Support/Speakin
- Uses CPU + Neural Engine for optimal performance
- Returns transcribed text stripped of timestamps/special tokens

**HotkeyMonitor.swift** - Global keyboard event monitoring:
- Requires Accessibility permission
- Monitors CGEvent stream for right Option key (keyCode 61)
- Publishes keyDown/keyUp events via Combine
- Must be properly stopped/started when permissions change

**TextInserter.swift** - Cursor position text injection:
- Primary: Uses AppleScript to inject text at cursor
- Fallback: Copies to clipboard if AppleScript fails
- Requires Accessibility permission for reliable injection

### Concurrency Model

- **@MainActor isolation**: Most UI-related classes (AppDelegate, AppState, TranscriptionEngine, MenuBarController)
- **nonisolated methods**: AudioRecorder callback handlers (processAudioBuffer, writeBatchedBuffers)
- **Actor-safe shared instances**: All singletons use @MainActor or nonisolated(unsafe) appropriately
- **Async/await**: Used for model initialization and transcription
- **Combine**: Used for hotkey events and state observation

### Key Design Patterns

1. **Buffer Batching** (AudioRecorder):
   - Problem: File writes every 256ms caused queue backup and timeout errors
   - Solution: Accumulate 10 buffers, write once per 2.5 seconds
   - Trade-off: ~80KB memory overhead for 90% fewer disk operations

2. **Async Completion Callbacks** (stopRecording/cancelRecording):
   - Audio engine stops immediately (< 1ms)
   - Background queue waits for pending writes (up to 5s timeout)
   - Completion handler called on main thread when done
   - Prevents main thread blocking during shutdown

3. **State Machine** (AppState):
   - Icon states: idle → listening → processing → success/error → idle
   - Ephemeral states (success/error) auto-revert to idle after 400ms
   - All state transitions go through dedicated methods

4. **Permission Polling** (PermissionManager):
   - Initial check/request at launch
   - Poll accessibility permission every 500ms if denied
   - Automatically continues initialization when granted

## Important Implementation Details

### Audio Format Requirements

AVAudioFile has strict format requirements that caused the original -10877 crash:
- **On-disk format**: 16-bit PCM, 16kHz, mono (compact for WhisperKit)
- **Processing format**: Float32 non-interleaved, 16kHz, mono (required by AVAudioFile.write())
- **Key insight**: You MUST convert to processingFormat, not the raw 16-bit format
- AudioRecorder handles this conversion in the processingQueue before writing

### Thread Safety Considerations

- **Core Audio thread**: Do ZERO work. Capture buffer (ARC retains) and dispatch immediately
- **Processing queue**: Format conversion, buffer accumulation (fast operations)
- **Write queue**: Disk I/O only (slow operations, completely decoupled)
- **Main actor**: All UI updates, state management, initialization
- Use `nonisolated(unsafe)` for properties accessed from multiple isolation domains

### Timer Usage

IconStateManager uses DispatchSourceTimer on background queue:
- **Why**: Main RunLoop timers compete with audio I/O scheduling
- **Pattern**: Timer fires on background queue, updates UI on main queue
- **Cleanup**: Cancel timer (not invalidate) for DispatchSourceTimer

## Dependencies

- **WhisperKit** (0.9.0+): On-device speech recognition using Apple's MLX
  - Downloads ~300MB model on first launch
  - Stored in ~/Library/Application Support/Speakin/models/
  - Uses CPU + Neural Engine compute units

## Permissions Required

1. **Microphone**: Required for audio recording (standard macOS permission)
2. **Accessibility**: Required for:
   - Global hotkey monitoring (CGEvent stream)
   - Text insertion at cursor position (AppleScript/AXUIElement)

Both permissions are requested at launch via PermissionManager.

## File Storage

- **Models**: `~/Library/Application Support/Speakin/models/openai_whisper-small/`
- **Temporary audio**: `~/Library/Caches/Speakin/temp_recording_[UUID].wav`
- **Cleanup**: Temporary files deleted after transcription or on app termination

## Known Issues & Gotchas

1. **Swift 6 Concurrency**: Project uses `nonisolated(unsafe)` for actor-safe singleton properties. This is correct but will require migration to true actor isolation in future Swift versions.

2. **Xcode vs SPM**: Project has both Package.swift and Speakin.xcodeproj. Always use Xcode for development - the Package.swift is primarily for dependency resolution.

3. **Model Download**: First launch can take 5-10 minutes depending on network speed. Progress is shown in a modal window.

4. **Accessibility Permission**: Cannot be requested programmatically. User must manually enable in System Settings > Privacy & Security > Accessibility. App polls every 500ms until granted.

5. **Audio Format Crash Prevention**: Never write directly to AVAudioFile from Core Audio thread. Always dispatch to background queue with copied buffer data. See AudioRecorder.swift for implementation pattern.
