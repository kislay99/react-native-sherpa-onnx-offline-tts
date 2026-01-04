const path = require('path');
const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');

const projectRoot = __dirname; // example/
const workspaceRoot = path.resolve(projectRoot, '..'); // repo root

module.exports = mergeConfig(getDefaultConfig(projectRoot), {
  watchFolders: [workspaceRoot],
  resolver: {
    // Force metro to resolve *all* packages from the repo root node_modules
    extraNodeModules: new Proxy(
      {},
      {
        get: (_, name) => path.join(workspaceRoot, 'node_modules', name),
      }
    ),
    nodeModulesPaths: [
      path.join(workspaceRoot, 'node_modules'),
      path.join(projectRoot, 'node_modules'),
    ],
  },
});
