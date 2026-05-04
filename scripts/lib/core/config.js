const fs = require('fs');
const path = require('path');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..');

function loadConfig() {
  const configPath = path.join(PROJECT_ROOT, 'config.json');
  if (!fs.existsSync(configPath)) {
    console.error('config.json not found. Run the CLAUDE.md wizard to initialize.');
    process.exit(1);
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));

  // Apply defaults from config.example.json
  const examplePath = path.join(PROJECT_ROOT, 'config.example.json');
  if (fs.existsSync(examplePath)) {
    const defaults = JSON.parse(fs.readFileSync(examplePath, 'utf8'));
    return deepMerge(defaults, config);
  }
  return config;
}

function deepMerge(target, source) {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      result[key] = deepMerge(result[key] || {}, source[key]);
    } else {
      result[key] = source[key];
    }
  }
  return result;
}

module.exports = { loadConfig, PROJECT_ROOT };
