// POSTGRES_URL comes from this checkout's .env (gitignored), so no credential is tracked here.
const fs = require('fs');
const path = require('path');

function fromEnvFile(key) {
  const file = path.join(__dirname, '.env');
  const line = fs.readFileSync(file, 'utf8').split(/\r?\n/).find((l) => l.startsWith(key + '='));
  const value = line && line.slice(key.length + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
  if (!value) throw new Error(key + ' is missing from ' + file);
  return value;
}

module.exports = {
  apps: [{
    name: 'hybrid-rag-api',
    script: 'koi-query-api.ts',
    interpreter: '/home/darren/.bun/bin/bun',
    cwd: '/opt/projects/koi-processor',
    env: {
      POSTGRES_URL: fromEnvFile('POSTGRES_URL'),
      DEBUG_GRAPH_EXPANSION: 'false',
      ENABLE_POLYSEMY_RERANK: 'true',
      DEBUG_POLYSEMY_RERANK: 'false',
      ENABLE_GRAPHRAG_CONTEXT: 'true'
    },
    out_file: 'logs/pm2-hybrid-rag.log',
    error_file: 'logs/pm2-hybrid-rag-error.log'
  }]
};
