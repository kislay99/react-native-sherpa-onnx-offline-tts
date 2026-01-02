# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

A React Native library providing offline Text-to-Speech (TTS) using Sherpa-ONNX. Wraps the native Sherpa-ONNX library for both iOS (Swift) and Android (Kotlin), allowing on-device speech synthesis with ONNX models (particularly Piper/VITS models).

## Commands

### Setup and Installation
```bash
# Install dependencies (Yarn workspaces required, npm NOT supported)
yarn

# iOS: Install pods (required after install or dependency changes)
cd example/ios && pod install && cd ../..
# or
npx pod-install
```

### Development

```bash
# Start Metro bundler
yarn example start

# Run example app
yarn example android    # Android
yarn example ios        # iOS

# Build example app
yarn example build:android
yarn example build:ios
```

### Testing and Quality

```bash
# Type checking
yarn typecheck

# Linting
yarn lint
yarn lint --fix

# Run tests
yarn test
```

### Library Build

```bash
# Build library (runs automatically on prepare)
yarn prepare    # Runs react-native-builder-bob to generate lib/ output

# Clean build artifacts
yarn clean
```

### Publishing

```bash
# Release new version (uses release-it with conventional-changelog)
yarn release
```

## Architecture

### Project Structure

- **Monorepo**: Managed with Yarn workspaces
  - Root: Library package
  - `example/`: Demo app showing library usage
- **Build System**: react-native-builder-bob generates CommonJS, ES Module, and TypeScript declarations
- **Native Modules**:
  - iOS: Swift implementation (`ios/`)
  - Android: Kotlin implementation (`android/src/main/java/com/sherpaonnxofflinetts/`)

### Key Components

#### JavaScript Layer (`src/index.tsx`)
- Exports `TTSManager` singleton with methods:
  - `initialize(modelConfigJson)`: Initialize with ONNX model config
  - `generateAndPlay(text, speakerId, speed)`: Generate and stream audio
  - `generate(text, speakerId, speed)`: Generate audio file, return path
  - `stopPlaying()`: Stop playback
  - `addVolumeListener(callback)`: Subscribe to RMS volume updates
  - `deinitialize()`: Free native resources
- Uses `NativeModules` and `NativeEventEmitter` for native bridge

#### iOS Native (`ios/`)
- **SherpaOnnxOfflineTts.swift**: Main module exposing methods to React Native
- **AudioPlayer.swift**: Handles audio playback with volume monitoring
- **ViewModel.swift**: TTS model management
- **SherpaOnnx.swift**: Bridge to Sherpa-ONNX C++ library
- Dependencies: Uses vendored xcframeworks (`onnxruntime.xcframework`, `sherpa-onnx.xcframework`)
- **Preinstall**: `scripts/download-build-ios.js` downloads Sherpa-ONNX iOS frameworks during `npm install`

#### Android Native (`android/src/main/java/com/sherpaonnxofflinetts/`)
- **TTSManagerModule.kt**: Main React Native module
- **AudioPlayer.kt**: Audio playback with volume callbacks
- **TTSManagerPackage.kt**: Package registration
- **AudioPlayerDelegate.kt**: Callback interface for audio events
- Uses Sherpa-ONNX Android AAR (bundled or downloaded)

### Model Configuration

Models are configured via JSON string passed to `initialize()`:
```json
{
  "modelPath": "/absolute/path/to/model.onnx",
  "tokensPath": "/absolute/path/to/tokens.txt",
  "dataDirPath": "/absolute/path/to/espeak-ng-data"
}
```

Models must be downloaded/extracted to device filesystem at runtime (see README Quick Start).

### Native Dependencies

#### iOS
- Sherpa-ONNX v1.10.26 iOS frameworks downloaded via `scripts/download-build-ios.js`
- Frameworks stored in `build-ios/` directory (not committed to git)
- Minimum iOS: 16.0 (see podspec)

#### Android
- Sherpa-ONNX Android library (version specified in build.gradle)
- Minimum Android: API 21 (Android 5.0)
- Supports armeabi-v7a and arm64-v8a architectures by default

## Development Patterns

### Testing Library Changes

1. Make changes to library source (`src/`, `ios/`, `android/`)
2. JavaScript changes: Hot reload works automatically in example app
3. Native changes: Rebuild example app (`yarn example android/ios`)
4. To edit native code in IDEs:
   - iOS: Open `example/ios/SherpaOnnxOfflineTtsExample.xcworkspace` in Xcode
     - Find library source: Pods → Development Pods → react-native-sherpa-onnx-offline-tts
   - Android: Open `example/android` in Android Studio
     - Find library source: react-native-sherpa-onnx-offline-tts under Android

### Commit Conventions

Follow conventional commits specification:
- `feat:` - New features
- `fix:` - Bug fixes
- `refactor:` - Code refactoring
- `docs:` - Documentation changes
- `test:` - Test changes
- `chore:` - Tooling/config changes

Pre-commit hooks enforce this format via commitlint.

### Adding Native Functionality

1. Add method to native module (TTSManagerModule.kt / SherpaOnnxOfflineTts.swift)
2. Add corresponding TypeScript signature to `src/index.tsx`
3. Export method from default export
4. Rebuild example app to test
5. Add tests if applicable

### Working with ONNX Models

- Models are NOT bundled with the library
- Example app demonstrates download/extraction pattern using react-native-fs and react-native-zip-archive
- Models typically from: https://github.com/k2-fsa/sherpa-onnx/releases (Piper voices)
- All file paths must be absolute paths on device filesystem
