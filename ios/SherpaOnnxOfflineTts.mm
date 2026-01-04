#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(TTSManager, NSObject)

// Initialize method exposed to React Native
RCT_EXTERN_METHOD(initializeTTS:(double)sampleRate channels:(NSInteger)channels modelId:(NSString *)modelId)

// Generate and Play method exposed to React Native
RCT_EXTERN_METHOD(generateAndPlay:(NSString *)text 
                  sid:(NSInteger)sid 
                  speed:(double)speed 
                  resolver:(RCTPromiseResolveBlock)resolver 
                  rejecter:(RCTPromiseRejectBlock)rejecter)

// Deinitialize method exposed to React Native
RCT_EXTERN_METHOD(deinitialize)

RCT_EXTERN_METHOD(generateAndSave:(NSString *)text
                  path:(NSString *)path
                  fileType:(NSString *)fileType
                  resolver:(RCTPromiseResolveBlock)resolver
                  rejecter:(RCTPromiseRejectBlock)rejecter)

@end
