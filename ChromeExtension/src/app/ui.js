/** Builds a text node element without interpreting authored text or page metadata as HTML. */
export function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

/** Announces a transient local operation result. */
export function notify(message) {
  const toast = document.querySelector('#toast');
  clearTimeout(notify.timeout);
  toast.textContent = message;
  toast.hidden = false;
  notify.timeout = setTimeout(() => { toast.hidden = true; }, 6500);
}

/** Returns a readable origin label without trusting a report URL as markup. */
export function pageLabel(context) {
  try { return new URL(context.url).host; } catch { return 'Manual report'; }
}

/** Renders a saved report as an accessible inbox row. */
export function issueRow(issue, selected, onSelect, onOpen) {
  const row = element('article', 'issue-row');
  const checkbox = element('input');
  checkbox.type = 'checkbox';
  checkbox.checked = selected;
  checkbox.setAttribute('aria-label', `Select ${issue.title || 'Untitled capture'}`);
  checkbox.onchange = () => onSelect(checkbox.checked);
  const button = element('button', 'issue-link');
  button.append(element('span', 'issue-title', issue.title || 'Untitled capture'));
  const meta = element('span', 'issue-meta', `${issue.id.slice(0, 8)} · ${issue.type} · ${pageLabel(issue.context)}`);
  if (issue.tags.length) meta.append(' · ', element('span', 'issue-tag', issue.tags.join(', ')));
  button.append(meta);
  button.onclick = onOpen;
  row.append(checkbox, button, element('span', 'issue-status', issue.draft ? '◧ Draft' : issue.status === 'Open' ? '○ Open' : '✓ Resolved'),
    element('time', 'issue-date', new Date(issue.createdAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })));
  return row;
}
