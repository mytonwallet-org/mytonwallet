import type { Table, UpdateSpec } from 'dexie';

const IGNORED_DEXIE_ERRORS = new Set(['AbortError', 'BulkError', 'UnknownError']);

async function tryDbQuery<T>(cb: () => Promise<T>) {
  try {
    return await cb();
  } catch (error: any) {
    if (IGNORED_DEXIE_ERRORS.has(error?.name)) return undefined;
    else throw error;
  }
}

export class DbRepository<T> {
  table: Table<T>;

  constructor(table: Table<T>) {
    this.table = table;
  }

  all() {
    return this.table.toArray();
  }

  find(where: {
    [key: string]: any;
  }) {
    return tryDbQuery(() => {
      return this.table.where(where).toArray();
    });
  }

  put(item: T) {
    return tryDbQuery(() => {
      return this.table.put(item);
    });
  }

  bulkPut(items: T[]) {
    return tryDbQuery(() => {
      return this.table.bulkPut(items);
    });
  }

  update(key: string[], update: UpdateSpec<T>) {
    return tryDbQuery(() => {
      return this.table.update(key, update);
    });
  }

  delete(key: string[]) {
    return tryDbQuery(() => {
      return this.table.delete(key);
    });
  }

  deleteWhere(where: {
    [key: string]: any;
  }) {
    return tryDbQuery(() => {
      return this.table.where(where).delete();
    });
  }

  clear() {
    return tryDbQuery(() => {
      return this.table.clear();
    });
  }
}
