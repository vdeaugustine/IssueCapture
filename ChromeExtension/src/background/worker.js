import { createIssue, putIssue } from '../data/store.js';
import { readPageContext } from './page-context.js';

let capturing = false;

async function openInbox(id = '') {
  await chrome.tabs.create({ url: chrome.runtime.getURL(`src/app/app.html${id ? `#issue=${id}` : ''}`) });
}

async function capturePage() {
  if (capturing) throw new Error('A capture is already in progress.');
  capturing = true;
  try {
    const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    if (!tab?.id || !/^https?:\/\//i.test(tab.url ?? '')) {
      throw new Error('Open an HTTP or HTTPS page to capture. Use a text report for browser settings or restricted pages.');
    }
    const [{ result: context }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id }, func: readPageContext
    });
    const [active] = await chrome.tabs.query({ active: true, windowId: tab.windowId });
    if (active?.id !== tab.id || active.url !== context.url) {
      throw new Error('The active page changed. Invoke capture again on the page you want.');
    }
    const screenshot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' });
    const [after] = await chrome.tabs.query({ active: true, windowId: tab.windowId });
    if (after?.id !== tab.id || after.url !== context.url) {
      throw new Error('The page changed during capture. Invoke capture again.');
    }
    const issue = createIssue(context, screenshot);
    await putIssue(issue);
    await openInbox(issue.id);
  } finally {
    capturing = false;
  }
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || !['capture', 'inbox', 'text'].includes(message?.action)) return;
  const operation = message.action === 'capture' ? capturePage()
    : message.action === 'inbox' ? openInbox() : createTextReport();
  operation.then(() => respond({ ok: true })).catch(error => respond({ error: error.message }));
  return true;
});

async function createTextReport() {
  const issue = createIssue();
  await putIssue(issue);
  await openInbox(issue.id);
}

chrome.commands.onCommand.addListener(command => {
  if (command !== 'capture-issue') return;
  capturePage().catch(async error => {
    // The inbox displays command failures without retaining any page evidence.
    await chrome.tabs.create({ url: chrome.runtime.getURL(`src/app/app.html#error=${encodeURIComponent(error.message)}`) });
  });
});
