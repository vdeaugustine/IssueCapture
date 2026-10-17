import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { readdir } from 'node:fs/promises';
import { createZip } from '../src/export/zip.js';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(root, 'dist');
const destination = resolve(output, 'extension');
const manifest = JSON.parse(await readFile(resolve(root, 'manifest.json'), 'utf8'));
const metadata = JSON.parse(await readFile(resolve(root, 'package.json'), 'utf8'));
if (manifest.version !== metadata.version) throw new Error('Manifest and app version must match.');

async function checkScripts(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) await checkScripts(path);
    else if (entry.name.endsWith('.js')) {
      const result = spawnSync(process.execPath, ['--check', path], { encoding: 'utf8' });
      if (result.status !== 0) throw new Error(result.stderr || `Syntax check failed: ${path}`);
    }
  }
}
await checkScripts(resolve(root, 'src'));
await rm(output, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
await cp(resolve(root, 'src'), resolve(destination, 'src'), { recursive: true });
await cp(resolve(root, 'manifest.json'), resolve(destination, 'manifest.json'));
console.log(`Built IssueCapture Web ${manifest.version}: ${destination}`);
console.log('Load this directory unpacked in Chrome. No dependencies or bundler required.');

async function archiveFiles(directory, prefix = '') {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    const relative = `${prefix}${entry.name}`;
    if (entry.isDirectory()) files.push(...await archiveFiles(path, `${relative}/`));
    else files.push({ path: relative, content: new Uint8Array(await readFile(path)) });
  }
  return files;
}
const archive = createZip(await archiveFiles(destination));
const archivePath = resolve(output, `issuecapture-web-${manifest.version}.zip`);
await writeFile(archivePath, new Uint8Array(await archive.arrayBuffer()));
console.log(`Packaged extension: ${archivePath}`);
