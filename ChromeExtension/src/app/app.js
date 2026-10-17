import { createIssue, getIssue, listIssues, putIssue } from '../data/store.js';
import { copyText, download, exportArchive } from '../export/reports.js';
import { issueRow, notify } from './ui.js';
import { setupEditor } from './editor.js';

let issues = [];
let view = 'all';
let busy = false;
const selected = new Set();
const openEditor = setupEditor(refresh);
const query = selector => document.querySelector(selector);

function visibleIssues() {
  const search = query('#search').value.toLocaleLowerCase();
  const type = query('#type-filter').value;
  return issues.filter(issue => {
    const matchesView = view === 'all' || (view === 'draft' ? issue.draft : !issue.draft && issue.status === view);
    const text = [issue.title, issue.description, issue.expected, issue.steps, issue.id, issue.context.url,
      issue.context.pageTitle, ...issue.tags].filter(Boolean).join(' ').toLocaleLowerCase();
    return matchesView && (!type || issue.type === type) && (!search || text.includes(search));
  });
}

function render() {
  const visible = visibleIssues();
  const open = issues.filter(issue => !issue.draft && issue.status === 'Open').length;
  const resolved = issues.filter(issue => !issue.draft && issue.status === 'Resolved').length;
  const counts = { 'all-count': issues.length, 'open-count': open, 'resolved-count': resolved,
    'draft-count': issues.filter(issue => issue.draft).length, 'heading-count': visible.length,
    'stat-total': issues.length, 'stat-open': open, 'stat-resolved': resolved,
    'stat-ready': issues.filter(issue => !issue.draft && !issue.exports.length).length };
  for (const [id, count] of Object.entries(counts)) query(`#${id}`).textContent = id.startsWith('stat-') ? String(count).padStart(2, '0') : count;
  const list = query('#issue-list');
  list.replaceChildren(...visible.map(issue => issueRow(issue, selected.has(issue.id), checked => {
    if (checked) selected.add(issue.id); else selected.delete(issue.id);
    renderSelection();
  }, () => openEditor(issue))));
  query('#empty-state').hidden = Boolean(visible.length);
  query('#empty-state h2').textContent = issues.length ? 'No issues in this view.' : 'A clearer picture starts here.';
  query('#empty-state p').textContent = issues.length ? 'Try another view or adjust your search and filters.' : 'Capture a page from the Chrome toolbar, or create a new issue and add your own screenshot.';
  query('#list-total').textContent = `${visible.length} of ${issues.length} issues`;
  renderSelection();
}

function renderSelection() {
  query('#selection-bar').hidden = selected.size === 0;
  query('#selection-count').textContent = `${selected.size} selected`;
}

async function refresh() {
  issues = await listIssues();
  for (const id of selected) if (!issues.some(issue => issue.id === id)) selected.delete(id);
  render();
}

async function newIssue() {
  try {
    const issue = createIssue({ browser: navigator.userAgent, language: navigator.language,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone });
    await putIssue(issue);
    await refresh();
    await openEditor(issue);
  } catch (error) { notify(`Could not create report: ${error.message}`); }
}

for (const id of ['new-issue', 'empty-new']) query(`#${id}`).onclick = newIssue;
query('#search').oninput = render;
query('#type-filter').onchange = render;
document.querySelectorAll('[data-view]').forEach(button => {
  button.onclick = () => {
    view = button.dataset.view;
    selected.clear();
    document.querySelectorAll('[data-view]').forEach(item => item.classList.toggle('active', item === button));
    const title = view === 'all' ? 'All issues' : view === 'draft' ? 'Drafts' : `${view} issues`;
    query('#breadcrumb').textContent = title;
    query('#view-title').firstChild.textContent = title;
    render();
  };
});
query('#select-all').onclick = () => {
  const visible = visibleIssues();
  const allSelected = visible.every(issue => selected.has(issue.id));
  for (const issue of visible) if (allSelected) selected.delete(issue.id); else selected.add(issue.id);
  render();
};
query('#help').onclick = () => query('#help-dialog').showModal();
query('#close-help').onclick = () => query('#help-dialog').close();

async function handoff(format) {
  if (busy || !selected.size) return;
  busy = true;
  query('#copy-selected').disabled = true;
  query('#export-selected').disabled = true;
  const reports = issues.filter(issue => selected.has(issue.id));
  let prepared = false;
  try {
    let exportedAt;
    if (format === 'zip') {
      const archive = await exportArchive(reports);
      exportedAt = archive.exportedAt;
      download(archive.blob, `IssueCapture-Web-${exportedAt.replace(/[:.]/g, '-')}.zip`);
    } else {
      exportedAt = new Date().toISOString();
      await navigator.clipboard.writeText(copyText(reports.map(issue => ({ ...issue,
        exports: [...issue.exports, { preparedAt: exportedAt, format }] }))));
    }
    prepared = true;
    // Read latest versions before updating history so another inbox's edits survive.
    for (const report of reports) {
      const latest = await getIssue(report.id);
      if (latest) await putIssue({ ...latest, exports: [...latest.exports, { preparedAt: exportedAt, format }] });
    }
    await refresh();
    notify(format === 'zip' ? 'ZIP prepared. Your saved reports are kept.' : 'Text copied. Use ZIP to include screenshot files.');
  } catch (error) { notify(`${prepared ? 'Handoff prepared, but export history could not be saved' : 'Handoff failed'}: ${error.message}`); }
  finally {
    busy = false;
    query('#copy-selected').disabled = false;
    query('#export-selected').disabled = false;
  }
}
query('#copy-selected').onclick = () => handoff('text');
query('#export-selected').onclick = () => handoff('zip');

window.addEventListener('focus', () => {
  if (!query('#editor').open) refresh().catch(error => notify(error.message));
});

async function start() {
  try {
    await refresh();
    const parameters = new URLSearchParams(location.hash.slice(1));
    if (parameters.has('error')) notify(parameters.get('error'));
    if (parameters.has('issue')) {
      const issue = await getIssue(parameters.get('issue'));
      if (issue) await openEditor(issue); else notify('This issue is no longer on this device.');
    }
    history.replaceState(null, '', location.pathname);
  } catch (error) { notify(`Local storage unavailable: ${error.message}. Enable site storage and reload.`); }
}
start();
