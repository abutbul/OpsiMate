import * as yaml from 'js-yaml';
import * as fs from 'fs';
import {Logger} from '@OpsiMate/shared';

const logger = new Logger('config');

export interface OpsimateConfig {
    server: {
        port: number;
        host: string;
    };
    database: {
        type?: 'sqlite' | 'postgres';
        path?: string;
        postgres?: {
            host: string;
            port: number;
            database: string;
            user: string;
            password: string;
        };
    };
    security: {
        private_keys_path: string;
    };
    vm: {
        try_with_sudo: boolean;
    };
}

let cachedConfig: OpsimateConfig | null = null;

export function loadConfig(): OpsimateConfig {
    if (cachedConfig) {
        return cachedConfig;
    }

    const configPath: string | null = process.env.CONFIG_FILE || null;

    if (!configPath || !fs.existsSync(configPath)) {
        logger.warn(`Config file not found starting from ${process.cwd()}, using defaults`);
        const defaultConfig = getDefaultConfig();
        cachedConfig = defaultConfig;
        return defaultConfig;
    }

    logger.info(`Loading config from: ${configPath}`);
    const configFile = fs.readFileSync(configPath, 'utf8');
    const config = yaml.load(configFile) as OpsimateConfig;

    // Validate required fields
    const dbType = config.database?.type || 'sqlite';
    if (!config.server?.port || 
        (dbType === 'sqlite' && !config.database?.path) ||
        (dbType === 'postgres' && !config.database?.postgres) ||
        !config.security?.private_keys_path) {
        logger.error('Invalid config file: missing required fields');
        throw new Error(`Invalid config file: ${configPath}`);
    }

    // Set default VM config if not provided
    if (!config.vm) {
        config.vm = {
            try_with_sudo: process.env.VM_TRY_WITH_SUDO !== 'false'
        };
    }

    cachedConfig = config;
    logger.info(`Configuration loaded from ${configPath}`);
    return config;
}

function getDefaultConfig(): OpsimateConfig {
    const dbType = (process.env.DATABASE_TYPE as 'sqlite' | 'postgres') || 'sqlite';
    
    const config: OpsimateConfig = {
        server: {
            port: 3001,
            host: 'localhost'
        },
        database: {
            type: dbType
        },
        security: {
            private_keys_path: '../../data/private-keys'
        },
        vm: {
            try_with_sudo: process.env.VM_TRY_WITH_SUDO !== 'false'
        }
    };

    if (dbType === 'postgres') {
        config.database.postgres = {
            host: process.env.POSTGRES_HOST || 'localhost',
            port: parseInt(process.env.POSTGRES_PORT || '5432'),
            database: process.env.POSTGRES_DB || 'opsimate',
            user: process.env.POSTGRES_USER || 'opsimate',
            password: process.env.POSTGRES_PASSWORD || 'opsimate_password'
        };
    } else {
        config.database.path = process.env.DATABASE_PATH || '../../data/database/opsimate.db';
    }

    return config;
}

// Helper function to get individual config sections
export function getServerConfig() {
    return loadConfig().server;
}

export function getDatabaseConfig() {
    return loadConfig().database;
}

export function getSecurityConfig() {
    return loadConfig().security;
}

export function getVmConfig() {
    return loadConfig().vm;
}
