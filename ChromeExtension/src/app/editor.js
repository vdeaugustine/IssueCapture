import { putIssue, deleteIssue } from '../data/store.js';
import { createAnnotator, loadImage } from './annotations.js';
import { element, notify } from './ui.js';

/** Manages one report editor, persisting notes as drafts while keeping originals unchanged. */
export function setupEditor(onUpdate) {
  const dialog = document.querySelector('#editor');
  const form = document.querySelector('#issue-form');
  const saveState = document.querySelector('#save-state');
  let issue = null;
  let annotator = null;
  let timer;
  let writeQueue = Promise.resolve();
  let dirty = false;
  let pendingWrites = 0;

  function readFields() {
    for (const name of ['title', 'description', 'expected', 'steps', 'type', 'status']) issue[name] = form.elements[name].value;
    issue.tags = [...new Set(form.elements.tags.value.split(',').map(tag => tag.trim()).filter(Boolean))];
    issue.includeScreenshot = form.elements.includeScreenshot.checked;
    issue.updatedAt = new Date().toISOString();
  }

  async function persist() {
    clearTimeout(timer);
    if (!issue || !dirty) { await writeQueue; return; }
    readFields();
    const snapshot = structuredClone(issue);
    dirty = false;
    saveState.textContent = 'Saving…';
    pendingWrites++;
    writeQueue = writeQueue.catch(() => {}).then(() => putIssue(snapshot));
    try {
      await writeQueue;
      saveState.textContent = issue.draft ? 'Draft saved locally' : 'Saved locally';
    } catch (error) {
      dirty = true;
      saveState.textContent = 'Save failed';
      notify(`Could not save: ${error.message}. Keep this editor open and export existing reports to free space.`);
      throw error;
    } finally { pendingWrites--; }
  }

  function changed() {
    dirty = true;
    saveState.textContent = 'Unsaved changes';
    clearTimeout(timer);
    timer = setTimeout(() => { persist().catch(() => {}); }, 500);
  }

  async function renderEvidence() {
    const hasImage = Boolean(issue.screenshot);
    for (const id of ['canvas-wrap', 'annotation-tools', 'include-label']) document.getElementById(id).hidden = !hasImage;
    document.querySelector('#attachment-label').hidden = hasImage;
    form.elements.includeScreenshot.checked = issue.includeScreenshot;
    annotator = hasImage ? await createAnnotator(document.querySelector('#evidence'), issue.screenshot, issue.annotations, changed) : null;
    for (const button of document.querySelectorAll('[data-tool]')) button.setAttribute('aria-pressed', String(button.dataset.tool === 'arrow'));
  }

  function renderContext() {
    const context = issue.context;
    const list = document.querySelector('#page-context');
    list.replaceChildren();
    const entries = [ ['Page', context.pageTitle || 'Manual report'], ['URL', context.url || 'Not captured'],
      ['Viewport', context.viewport ? `${context.viewport.width} × ${context.viewport.height} @ ${context.viewport.pixelRatio}×` : 'Not captured'],
      ['Scroll', context.scroll ? `${context.scroll.x}, ${context.scroll.y}` : 'Not captured'],
      ['Captured', new Date(issue.createdAt).toLocaleString()], ['Language', context.language || navigator.language],
      ['Timezone', context.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone],
      ['Browser', context.browser || navigator.userAgent] ];
    for (const [label, value] of entries) list.append(element('dt', '', label), element('dd', '', value));
  }

  form.addEventListener('input', event => { if (event.target.id !== 'attachment') changed(); });
  form.onsubmit = async event => {
    event.preventDefault();
    const submit = form.querySelector('[type=submit]');
    submit.disabled = true;
    issue.draft = false;
    dirty = true;
    try { await persist(); dialog.close(); await onUpdate(); notify('Issue saved. Context included.'); }
    catch { /* Save error is announced by persist; keep the editor open. */ }
    finally { submit.disabled = false; }
  };

  async function closeEditor() {
    try { await persist(); dialog.close(); await onUpdate(); } catch { /* Keep unsaved work visible. */ }
  }
  document.querySelector('#close-editor').onclick = closeEditor;
  dialog.addEventListener('cancel', event => { event.preventDefault(); closeEditor(); });
  document.querySelector('#delete-issue').onclick = async () => {
    if (!confirm('Permanently delete this issue and its screenshots from this device?')) return;
    clearTimeout(timer);
    try {
      await writeQueue.catch(() => {});
      await deleteIssue(issue.id);
      dirty = false;
      dialog.close();
      await onUpdate();
      notify('Issue deleted.');
    } catch (error) { notify(`Delete failed: ${error.message}`); }
  };
  document.querySelectorAll('[data-tool]').forEach(button => {
    button.onclick = () => {
      annotator?.setTool(button.dataset.tool);
      document.querySelectorAll('[data-tool]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    };
  });
  document.querySelector('#undo').onclick = () => annotator?.undo();
  document.querySelector('#attachment').onchange = async event => {
    const file = event.target.files[0];
    const attachmentIssueID = issue.id;
    if (!file || issue.screenshot) return;
    try {
      if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 20 * 1024 * 1024) throw new Error('Choose a PNG, JPEG, or WebP image under 20 MB.');
      const source = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
      });
      const image = await loadImage(source);
      if (image.naturalWidth * image.naturalHeight > 40000000) throw new Error('Choose an image under 40 megapixels.');
      if (issue.id !== attachmentIssueID || !dialog.open) return;
      issue.screenshot = source;
      issue.context.imageSource = 'manual attachment';
      issue.includeScreenshot = true;
      await renderEvidence();
      changed();
    } catch (error) { notify(error.message); }
  };
  window.addEventListener('beforeunload', event => {
    if (!dirty && !pendingWrites) return;
    event.preventDefault();
    event.returnValue = '';
  });

  return async current => {
    issue = structuredClone(current);
    dirty = false;
    form.reset();
    for (const name of ['title', 'description', 'expected', 'steps', 'type', 'status']) form.elements[name].value = issue[name];
    form.elements.tags.value = issue.tags.join(', ');
    document.querySelector('#editor-id').textContent = `${issue.draft ? 'DRAFT' : 'ISSUE'} / ${issue.id.slice(0, 8).toUpperCase()}`;
    saveState.textContent = 'Saved on this device';
    renderContext();
    dialog.showModal();
    try { await renderEvidence(); } catch (error) { notify(`Evidence could not be displayed: ${error.message}`); }
  };
}
