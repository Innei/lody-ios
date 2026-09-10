const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
// Expo DOM transforms embed absolute paths, so worktrees must not share entries.
config.cacheVersion += `:${__dirname}`;
module.exports = config;
