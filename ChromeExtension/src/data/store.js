const databasePromise = new Promise((resolve, reject) => {
  const request = indexedDB.open('issuecapture-web', 1);
  request.onupgradeneeded = () => request.result.createObjectStore('issues', { keyPath: 'id' });
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});

async function transaction(mode, operation) {
  const database = await databasePromise;
  return new Promise((resolve, reject) => {
    const current = database.transaction('issues', mode);
    const request = operation(current.objectStore('issues'));
    current.oncomplete = () => resolve(request.result);
    current.onerror = () => reject(current.error);
    current.onabort = () => reject(current.error ?? new Error('Local save was interrupted.'));
  });
}

/** Returns reports, newest first, including unfinished captures. */
export async function listIssues() {
  const issues = await transaction('readonly', store => store.getAll());
  return issues.sort((left, right) => right.createdAt.localeCompare(left.createdAt));
}

/** Reads one locally stored report. */
export function getIssue(id) {
  return transaction('readonly', store => store.get(id));
}

/** Commits a report and its original evidence in one transaction. */
export function putIssue(issue) {
  return transaction('readwrite', store => store.put(issue));
}

/** Permanently removes one local report and its evidence. */
export function deleteIssue(id) {
  return transaction('readwrite', store => store.delete(id));
}

/** Creates a browser-specific report; this schema is independent of the iOS package. */
export function createIssue(context = {}, screenshot = null) {
  const timestamp = new Date().toISOString();
  return {
    schemaVersion: 1, platform: 'web', id: crypto.randomUUID(),
    createdAt: timestamp, updatedAt: timestamp, draft: true,
    title: '', description: '', expected: '', steps: '', tags: [],
    type: 'Bug', status: 'Open', context, screenshot,
    includeScreenshot: Boolean(screenshot), annotations: [], exports: []
  };
}
