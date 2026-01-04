// App.tsx

import { useEffect, useState, useRef } from 'react';
import {
  View,
  Button,
  Animated,
  StyleSheet,
  Text,
  TextInput,
  ActivityIndicator,
  Alert,
} from 'react-native';
import TTSManager from 'react-native-sherpa-onnx-offline-tts'; // Import your native module
import RNFS from 'react-native-fs'; // For file system operations

const App = () => {
  // State variables
  const [volume, setVolume] = useState(0);
  const [downloadProgress, setDownloadProgress] = useState<number>(0);
  const [isDownloading, setIsDownloading] = useState<boolean>(false);
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [isInitialized, setIsintialized] = useState<boolean>(true);
  const [savePath, setSavePath] = useState(''); // optional
  const [status, setStatus] = useState('');
  // References
  const animatedScale = useRef(new Animated.Value(1)).current;
  const downloadJobIdRef = useRef<number | null>(null); // To track the download job

  const onSaveAudio = async () => {
    try {
      setStatus('Saving...');
      const outPath: string = await TTSManager.generateAndSave(
        'Hello world, this is Lorem Ipsum.', // whatever your current text state variable is
        savePath.trim() || undefined
      );
      setStatus(`Audio saved at: ${outPath}`);
      console.log('Audio saved at:', outPath);
    } catch (e: any) {
      console.error(e);
      setStatus(`Save failed: ${e?.message ?? String(e)}`);
    }
  };

  const initializeTTS = async () => {
    try {
      setIsDownloading(true);
      setDownloadProgress(0);

      // ---- Hugging Face config ----
      const HF_REPO_ID = 'csukuangfj/vits-piper-en_US-ryan-medium';
      const HF_REVISION = 'main';

      const encodePath = (p: string) =>
        p.split('/').map(encodeURIComponent).join('/');

      const hfResolveUrl = (pathInRepo: string) =>
        `https://huggingface.co/${HF_REPO_ID}/resolve/${HF_REVISION}/${encodePath(
          pathInRepo
        )}?download=true`;

      const hfModelMetaUrl = `https://huggingface.co/api/models/${HF_REPO_ID}`;

      // ---- Local paths (keep your existing extracted layout) ----
      const extractPath = `${RNFS.DocumentDirectoryPath}/extracted`;
      const modelDir = `${extractPath}/vits-piper-en_US-ryan-medium`;

      const modelPath = `${modelDir}/en_US-ryan-medium.onnx`;
      const tokensPath = `${modelDir}/tokens.txt`;
      const dataDirPath = `${modelDir}/espeak-ng-data`;

      const ensureDirForFile = async (filePath: string) => {
        const dir = filePath.slice(0, filePath.lastIndexOf('/'));
        if (dir) await RNFS.mkdir(dir);
      };

      const dirHasFiles = async (dirPath: string) => {
        try {
          const items = await RNFS.readDir(dirPath);
          return items.length > 0;
        } catch {
          return false;
        }
      };

      await RNFS.mkdir(modelDir);

      // ---- If already downloaded, init immediately ----
      const alreadyThere =
        (await RNFS.exists(modelPath)) &&
        (await RNFS.exists(tokensPath)) &&
        (await RNFS.exists(dataDirPath)) &&
        (await dirHasFiles(dataDirPath));

      if (alreadyThere) {
        setIsintialized(true);
        setIsDownloading(false);
        setDownloadProgress(100);

        const modelIdJson = JSON.stringify({
          modelPath,
          tokensPath,
          dataDirPath,
        });
        await TTSManager.initialize(modelIdJson);
        console.log(
          'TTS Initialized Successfully with existing HuggingFace model'
        );
        return;
      }

      // ---- List all files in the repo (so we can download espeak-ng-data/*) ----
      const metaRes = await fetch(hfModelMetaUrl);
      if (!metaRes.ok) {
        throw new Error(
          `Failed to fetch Hugging Face metadata: ${metaRes.status}`
        );
      }

      const metaJson: any = await metaRes.json();
      const siblings: Array<{ rfilename: string; size?: number }> =
        metaJson?.siblings ?? [];

      const requiredRepoFiles = [
        'en_US-ryan-medium.onnx',
        'tokens.txt',
        // download *all* files under espeak-ng-data/
        ...siblings
          .map((s) => s.rfilename)
          .filter((name) => name.startsWith('espeak-ng-data/')),
      ];

      // De-dupe while preserving order
      const seen = new Set<string>();
      const filesToDownload = requiredRepoFiles.filter((f) => {
        if (seen.has(f)) return false;
        seen.add(f);
        return true;
      });

      // Build size map (used for overall progress)
      const sizeByFile = new Map<string, number>();
      for (const s of siblings) {
        if (typeof s?.rfilename === 'string' && typeof s?.size === 'number') {
          sizeByFile.set(s.rfilename, s.size);
        }
      }

      // If HF API didn't return sizes for some, treat as 0 (progress still works but less accurate)
      const totalBytes = filesToDownload.reduce(
        (sum, f) => sum + (sizeByFile.get(f) ?? 0),
        0
      );

      // Track per-file bytes written for aggregate progress
      const writtenByFile = new Map<string, number>();
      let completedBytes = 0;

      const updateOverallProgress = () => {
        if (totalBytes <= 0) return; // unknown total, skip aggregate
        let writtenSum = completedBytes;
        for (const v of writtenByFile.values()) writtenSum += v;
        const pct = Math.min(100, (writtenSum / totalBytes) * 100);
        setDownloadProgress(pct);
      };

      // Pre-mark bytes for files that already exist
      for (const repoPath of filesToDownload) {
        const localPath = `${modelDir}/${repoPath}`;
        if (await RNFS.exists(localPath)) {
          completedBytes += sizeByFile.get(repoPath) ?? 0;
        }
      }
      updateOverallProgress();

      // ---- Download sequentially (simpler + stable progress) ----
      for (const repoPath of filesToDownload) {
        const localPath = `${modelDir}/${repoPath}`;

        // Skip if already present
        const exists = await RNFS.exists(localPath);
        if (exists) continue;

        await ensureDirForFile(localPath);

        const fromUrl = hfResolveUrl(repoPath);

        await new Promise<void>((resolve, reject) => {
          writtenByFile.set(repoPath, 0);

          const ret = RNFS.downloadFile({
            fromUrl,
            toFile: localPath,
            background: true,
            discretionary: true,
            progressDivider: 1,
            begin: () => {
              console.log('Download started:', repoPath);
            },
            progress: (res: RNFS.DownloadProgressCallbackResult) => {
              // bytesWritten is for this file
              writtenByFile.set(repoPath, res.bytesWritten);
              updateOverallProgress();
            },
          });

          // Keep last job id (best-effort compatibility with your cancel logic)
          downloadJobIdRef.current = ret.jobId;

          ret.promise
            .then((result) => {
              if (result.statusCode === 200) {
                // Move this file's bytes into completedBytes and clear active tracking
                completedBytes += sizeByFile.get(repoPath) ?? 0;
                writtenByFile.delete(repoPath);
                updateOverallProgress();
                console.log('Downloaded:', repoPath);
                resolve();
              } else {
                reject(
                  new Error(
                    `Failed to download ${repoPath}. Status: ${result.statusCode}`
                  )
                );
              }
            })
            .catch(reject);
        });
      }

      // Ensure minimum required files exist before init
      const ok =
        (await RNFS.exists(modelPath)) &&
        (await RNFS.exists(tokensPath)) &&
        (await RNFS.exists(dataDirPath)) &&
        (await dirHasFiles(dataDirPath));

      if (!ok) {
        throw new Error(
          'Model download incomplete: missing model/tokens/espeak-ng-data'
        );
      }

      setIsDownloading(false);
      setDownloadProgress(100);

      const modelIdJson = JSON.stringify({
        modelPath,
        tokensPath,
        dataDirPath,
      });
      await TTSManager.initialize(modelIdJson);
      console.log('TTS Initialized Successfully with HuggingFace model');
    } catch (error) {
      setIsDownloading(false);
      setDownloadProgress(0);
      console.error('Error initializing TTS:', error);
      Alert.alert(
        'Initialization Error',
        'Failed to initialize TTS. Please try again.'
      );
    }
  };

  useEffect(() => {
    const subscription = TTSManager.addVolumeListener((v: any) => {
      setVolume(v);
    });

    console.log('VolumeUpdate listener registered');

    // Initialize TTS after registering the listener
    initializeTTS();

    // Cleanup on unmount
    return () => {
      subscription.remove();
      TTSManager.deinitialize();

      // Cancel any ongoing download if necessary
      if (downloadJobIdRef.current) {
        RNFS.stopDownload(downloadJobIdRef.current);
      }

      console.log('VolumeUpdate listener removed and TTSManager deinitialized');
    };
  }, [animatedScale]);

  /**
   * Handles the Play Audio button press.
   */
  const handlePlay = async () => {
    try {
      const text =
        'In the grand tapestry of the cosmos, every star tells a story, every galaxy holds a secret.';
      const sid = 0; // Example speaker ID or similar
      const speed = 0.85; // Normal speed
      if (!isInitialized) {
        console.log('isInitialized: ', isInitialized);
        await initializeTTS();
      }
      setIsPlaying(true);
      await TTSManager.generateAndPlay(text, sid, speed);
      setIsPlaying(false);
    } catch (error) {
      setIsPlaying(false);
      console.error('Error playing TTS:', error);
      Alert.alert('Playback Error', 'Failed to play TTS. Please try again.');
    }
  };

  /**
   * Handles the Stop Audio button press.
   */
  const handleStop = () => {
    TTSManager.deinitialize();
    setIsintialized(false);
    setIsPlaying(false);
    console.log('Playback stopped.');
  };

  return (
    <View style={styles.container}>
      {/* Display Download Progress */}
      {isDownloading && (
        <View style={styles.downloadContainer}>
          <ActivityIndicator size="large" color="#0000ff" />
          <Text style={styles.downloadText}>
            Downloading Model: {downloadProgress.toFixed(2)}%
          </Text>
        </View>
      )}

      {/* Main Content */}
      {!isDownloading && (
        <>
          <Animated.View
            style={[
              styles.circle,
              {
                transform: [{ scale: animatedScale }],
              },
            ]}
          />
          <View style={styles.buttons}>
            <Button
              title="Play Audio"
              onPress={handlePlay}
              disabled={isPlaying}
            />
            <Button
              title="Stop Audio"
              onPress={handleStop}
              disabled={!isPlaying}
            />
          </View>
          <Text style={{ marginTop: 16 }}>Save path (optional)</Text>
          <TextInput
            value={savePath}
            onChangeText={setSavePath}
            placeholder="Absolute .wav path OR directory (leave empty for default)"
            style={{ borderWidth: 1, padding: 8, marginTop: 8 }}
          />

          <View style={{ marginTop: 12 }}>
            <Button title="Save Audio" onPress={onSaveAudio} />
          </View>

          {status ? <Text style={{ marginTop: 12 }}>{status}</Text> : null}

          <View style={styles.volumeContainer}>
            <Text>Current Volume: {volume.toFixed(2)}</Text>
          </View>
        </>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center', // Center vertically
    alignItems: 'center', // Center horizontally
    backgroundColor: '#F5FCFF',
  },
  circle: {
    width: 100,
    height: 100,
    borderRadius: 50, // Makes it a circle
    backgroundColor: 'skyblue',
    marginBottom: 50,
  },
  buttons: {
    width: '80%',
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 20,
  },
  downloadContainer: {
    alignItems: 'center',
  },
  downloadText: {
    marginTop: 10,
    fontSize: 16,
  },
  volumeContainer: {
    marginTop: 20,
  },
});

export default App;
