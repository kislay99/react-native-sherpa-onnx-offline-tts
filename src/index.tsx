import { NativeModules, NativeEventEmitter } from 'react-native';

const nativeTTS = NativeModules.TTSManager;
const emitter = new NativeEventEmitter(nativeTTS);

const addVolumeListener = (callback: (v: number) => void) => {
  let sub = emitter.addListener('VolumeUpdate', (event: any) => {
    callback(event.volume);
  });
  return sub;
};

export default {
  initialize: (modelId: string) => nativeTTS.initializeTTS(22050, 1, modelId),
  generateAndPlay: (text: any, sid: any, speed: any) =>
    nativeTTS.generateAndPlay(text, sid, speed),
  deinitialize: () => nativeTTS.deinitialize(),
  addVolumeListener,
};
