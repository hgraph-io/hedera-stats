export const config = {
  statsDb: {
    host: process.env.STATS_DB_HOST || 'localhost',
    port: parseInt(process.env.STATS_DB_PORT || '5433'),
    database: process.env.STATS_DB_NAME || 'hedera_stats',
    user: process.env.STATS_DB_USER || 'postgres',
    password: process.env.STATS_DB_PASSWORD || 'postgres',
  },
  mirrorNode: {
    host: process.env.MIRROR_NODE_HOST || '',
    port: parseInt(process.env.MIRROR_NODE_PORT || '5432'),
    database: process.env.MIRROR_NODE_DB || 'hedera_mainnet',
    user: process.env.MIRROR_NODE_USER || '',
    password: process.env.MIRROR_NODE_PASSWORD || '',
  },
  prometheusEndpoint: process.env.PROMETHEUS_ENDPOINT || '',
};
