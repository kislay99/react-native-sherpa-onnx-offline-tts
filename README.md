# react-native-sherpa-onnx-offline-tts

A lightweight React Native wrapper around [Sherpa‑ONNX](https://github.com/k2-fsa/sherpa-onnx) that lets you run **100 % offline Text‑to‑Speech** on iOS and Android.

---

## ✨ Features

| | |
|---|---|
| 🔊 **Offline** – all synthesis happens on‑device, no network needed | ⚡ **Fast** – real‑time (or faster) generation on modern phones |
| 🎙️ **Natural voices** – drop‑in support for Piper / VITS ONNX models | 🛠️ **Simple API** – a handful of async methods you already know |

---

## 📦 Installation

```bash
# Add the library
npm install react-native-sherpa-onnx-offline-tts
# or
yarn add react-native-sherpa-onnx-offline-tts

# iOS only\	npx pod-install
```

> **Minimum versions**  |  Android 5.0 (API 21) • iOS 11

---

## 🚀 Quick Start

1. **Choose a model** – grab any [Piper](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ryan-medium.tar.bz2) voice ZIP (e.g. `vits-piper-en_US-ryan-medium.zip`) and host it yourself or bundle it with the app.
2. **Download & unzip** the archive into your app’s sandbox (the example below uses **react‑native‑fs** & **react‑native‑zip‑archive**).
3. **Create a config JSON** with absolute paths to `*.onnx`, `tokens.txt`, and the `espeak-ng-data` folder.
4. **Initialize**, then generate or stream speech.

```tsx
import TTSManager from 'react-native-sherpa-onnx-offline-tts';
import RNFS from 'react-native-fs';
import { unzip } from 'react-native-zip-archive';

const MODEL_URL =
  'https://example.com/vits-piper-en_US-ryan-medium.zip';

async function setupTTS() {
  const archive = `${RNFS.DocumentDirectoryPath}/vits.zip`;
  const extractRoot = `${RNFS.DocumentDirectoryPath}/extracted`;

  // 1️⃣  Download if missing
  if (!(await RNFS.exists(archive))) {
    await RNFS.downloadFile({ fromUrl: MODEL_URL, toFile: archive }).promise;
  }

  // 2️⃣  Unpack if first run
  if (!(await RNFS.exists(`${extractRoot}/vits-piper-en_US-ryan-medium`))) {
    await unzip(archive, extractRoot);
  }

  // 3️⃣  Point the engine to the files
  const base = `${extractRoot}/vits-piper-en_US-ryan-medium`;
  const cfg = {
    modelPath: `${base}/en_US-ryan-medium.onnx`,
    tokensPath: `${base}/tokens.txt`,
    dataDirPath: `${base}/espeak-ng-data`,
  };

  // 4️⃣  Initialise (only once per session)
  await TTSManager.initialize(JSON.stringify(cfg));
}

async function sayHello() {
  const text = 'Hello world – spoken entirely offline!';
  const speakerId = 0;   // Piper uses 0 for single‑speaker models
  const speed = 1.0;     // 1 == default, < 1 slower, > 1 faster

  await TTSManager.generateAndPlay(text, speakerId, speed);
}
```

---

## 📚 API Reference (Updated)

| Method | Signature | Description |
|--------|-----------|-------------|
| **initialize** | `(modelId: string): Promise<void>` | Initializes native TTS with the given `modelId` (internally uses 22050 Hz, mono). Call once before synthesis/playback. |
| **generateAndPlay** | `(text: string, speakerId: number, speed: number): Promise<void>` | Generates speech and plays it on the device speaker. Emits real-time volume updates while playing (if listener is attached). |
| **generateAndSave** | `(text: string, path?: string \| null, fileType?: 'wav'): Promise<string>` | Generates speech and saves it to disk. Returns the saved file path. **Only `'wav'` is supported right now**; omit `fileType` to default to `'wav'`. |
| **addVolumeListener** | `(cb: (volume: number) => void): EmitterSubscription` | Subscribes to real-time RMS volume callbacks during playback. Call `subscription.remove()` to unsubscribe. |
| **deinitialize** | `(): void` | Frees native resources; call when your app unmounts or you won’t use TTS for a while. |


---

## 🔊 Supported Models

* Any **Piper** VITS model (`*.onnx`) with matching `tokens.txt` and `espeak-ng-data` directory.
* Multi‑speaker models are supported – just pass the desired `speakerId`.

> Need other formats? Feel free to open an issue or pull request.

---

## 🛠️ Example App

A minimal, production‑ready example (downloads the model on first launch, shows a progress spinner, animates to mic volume, etc.) lives in **`example/App.tsx`** – the snippet below is an abridged version:

```tsx title="example/App.tsx"
const App = () => {
  /* full source lives in the repo */
  return (
    <View style={styles.container}>
      {isDownloading ? (
        <ProgressBar progress={downloadProgress} />
      ) : (
        <>
          <AnimatedCircle scale={volume} />
          <Button title="Play" onPress={handlePlay} disabled={isPlaying} />
          <Button title="Stop" onPress={handleStop} disabled={!isPlaying} />
        </>
      )}
    </View>
  );
};
```

## Building the source
```
# 1) Clone
git clone https://github.com/kislay99/react-native-sherpa-onnx-offline-tts.git
cd react-native-sherpa-onnx-offline-tts

# 2) Use repo Node version (requires nvm)
nvm install
nvm use

# 3) Install JS deps (repo uses Yarn via Corepack)
cd example
corepack enable
yarn install

# 4) Install iOS pods (Bundler-managed CocoaPods)
cd example/ios
gem install bundler
bundle install
rm -rf Pods Podfile.lock build
bundle exec pod install

# 5) Run on iOS Simulator
cd ..
open -a Simulator
yarn ios --simulator "iPhone 15"

# For checking simulator logs
xcrun simctl spawn booted log stream --style compact \
  --predicate 'process == "SherpaOnnxOfflineTtsExample"'

```

---

## 🤝 Contributing

Bug reports and PRs are welcome!  Please see [CONTRIBUTING.md](CONTRIBUTING.md) for the full development workflow.

---

## 📄 License

[MIT](LICENSE)

---

Made with ❤️ & [create‑react‑native‑library](https://github.com/callstack/react-native-builder-bob)

