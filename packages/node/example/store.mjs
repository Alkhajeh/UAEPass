import { rm } from 'node:fs/promises';

/**
 * In-memory entries with an `expiresAt` timestamp. Reads never return an expired entry.
 * Expired entries with a stored PDF pending provider cleanup get one last cleanup attempt.
 *
 * A production backend would keep this state in a shared store (for example Redis or a
 * database) so that it survives restarts and works across instances.
 */
export class ExpiringStore {
  #entries = new Map();
  #cleanup;

  constructor({ cleanup }) {
    this.#cleanup = cleanup;
  }

  get size() { return this.#entries.size; }

  has(id) { return this.#entries.has(id); }

  set(id, entry) { this.#entries.set(id, entry); }

  delete(id) { this.#entries.delete(id); }

  /** Returns the live entry for `id`, expiring it first when its lifetime has passed. */
  get(id) {
    const entry = this.#entries.get(id);
    if (entry?.expiresAt <= Date.now()) {
      this.#expire(id, entry);
      return undefined;
    }
    return entry;
  }

  /** Returns the first live entry that matches the predicate. */
  find(predicate) {
    for (const entry of this.#entries.values()) {
      if (entry.expiresAt > Date.now() && predicate(entry)) return entry;
    }
    return undefined;
  }

  sweep() {
    for (const id of [...this.#entries.keys()]) this.get(id);
  }

  /** Removes the entry if it is still current and deletes its stored PDF. */
  discard(id, entry) {
    if (this.#entries.get(id) === entry) this.#entries.delete(id);
    if (entry.job?.pdfPath) void rm(entry.job.pdfPath, { force: true }).catch(() => {});
  }

  #expire(id, entry) {
    const job = entry.job;
    if (entry.authorization || job?.busy) return;
    if (!job?.cleanupPending) return this.discard(id, entry);
    // Make one last attempt to remove the provider copy of a verified, stored PDF.
    job.busy = true;
    void this.#cleanup(job).finally(() => this.discard(id, entry));
  }
}
