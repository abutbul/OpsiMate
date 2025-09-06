import Database from 'better-sqlite3';
import { Pool, Client } from 'pg';
import path from 'path';
import fs from 'fs';
import { Logger } from '@OpsiMate/shared';
import { loadConfig } from '../config/config';

const logger = new Logger('dal/db');

export interface DatabaseInterface {
  prepare(sql: string): any;
  exec(sql: string): any;
  close(): void;
  transaction<T>(fn: () => T): T;
}

class SQLiteWrapper implements DatabaseInterface {
  private db: Database.Database;

  constructor(dbPath: string) {
    const absolutePath = path.isAbsolute(dbPath) 
      ? dbPath 
      : path.resolve(__dirname, dbPath);
    
    logger.info(`SQLite database is connecting to ${absolutePath}`);

    try {
      // Ensure the directory exists
      const dbDir = path.dirname(absolutePath);
      if (!fs.existsSync(dbDir)) {
        logger.info(`Creating database directory: ${dbDir}`);
        fs.mkdirSync(dbDir, { recursive: true });
      }

      this.db = new Database(absolutePath);
      logger.info(`SQLite database connected at ${absolutePath}`);
    } catch (error) {
      logger.error('SQLite connection error:', error);
      throw error;
    }
  }

  prepare(sql: string) {
    return this.db.prepare(sql);
  }

  exec(sql: string) {
    return this.db.exec(sql);
  }

  close() {
    this.db.close();
  }

  transaction<T>(fn: () => T): T {
    return this.db.transaction(fn)();
  }

  get raw() {
    return this.db;
  }
}

class PostgreSQLWrapper implements DatabaseInterface {
  private pgPool: Pool;

  constructor(config: { host: string; port: number; database: string; user: string; password: string }) {
    logger.info(`PostgreSQL database is connecting to ${config.host}:${config.port}/${config.database}`);
    
    this.pgPool = new Pool({
      host: config.host,
      port: config.port,
      database: config.database,
      user: config.user,
      password: config.password,
      max: 10,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    });

    logger.info('PostgreSQL database connected');
  }

  prepare(sql: string) {
    // Convert SQLite-style placeholders to PostgreSQL-style
    const pgSql = sql.replace(/\?/g, (match, offset) => {
      const count = (sql.substring(0, offset).match(/\?/g) || []).length + 1;
      return `$${count}`;
    });

    return {
      run: async (...params: any[]) => {
        const client = await this.pgPool.connect();
        try {
          const result = await client.query(pgSql, params);
          return { changes: result.rowCount, lastInsertRowid: result.rows[0]?.id };
        } finally {
          client.release();
        }
      },
      get: async (...params: any[]) => {
        const client = await this.pgPool.connect();
        try {
          const result = await client.query(pgSql, params);
          return result.rows[0];
        } finally {
          client.release();
        }
      },
      all: async (...params: any[]) => {
        const client = await this.pgPool.connect();
        try {
          const result = await client.query(pgSql, params);
          return result.rows;
        } finally {
          client.release();
        }
      }
    };
  }

  exec(sql: string) {
    return this.pgPool.query(sql);
  }

  close() {
    return this.pgPool.end();
  }

  transaction<T>(fn: () => T): T {
    // For PostgreSQL, we'll need to implement transactions differently
    // This is a simplified version - in practice, you'd want proper transaction handling
    return fn();
  }

  get pool() {
    return this.pgPool;
  }
}

export function initializeDb(): DatabaseInterface {
  const config = loadConfig();
  const dbType = config.database.type || 'sqlite';

  if (dbType === 'postgres' && config.database.postgres) {
    return new PostgreSQLWrapper(config.database.postgres);
  } else if (dbType === 'sqlite' && config.database.path) {
    return new SQLiteWrapper(config.database.path);
  } else {
    throw new Error(`Invalid database configuration: type=${dbType}`);
  }
}

export function runAsync<T = unknown>(fn: () => T): Promise<T> {
  return new Promise((resolve, reject) => {
    try {
      const result = fn();
      resolve(result);
    } catch (error) {
      reject(error);
    }
  });
}
