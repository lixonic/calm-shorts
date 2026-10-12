(() => {
  'use strict';
  const shapes = {
    leaf: '<path d="M20 3c0 10-3 17-10 17a6 6 0 0 1-6-6C4 7 11 4 20 3Z"/><path d="M4 21 15 10"/>',
    folder: '<path d="M3 7V5a2 2 0 0 1 2-2h5l3 3h6a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/><path d="M3 8h18"/>',
    portrait: '<rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 17h2"/>',
    landscape: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M17 11v2"/>',
    text: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8M8 12h8M8 16h5"/>',
    trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/>',
    play: '<path d="m8 4 13 8-13 8V4Z"/>',
    external: '<path d="M14 3h7v7M21 3l-9 9M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5"/>',
    upload: '<path d="M12 16V3m-5 5 5-5 5 5M3 15v4a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-4"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
    grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
    list: '<path d="M8 5h13M8 12h13M8 19h13M3 5h.1M3 12h.1M3 19h.1"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    restore: '<path d="M3 10a9 9 0 1 1 1 7M3 4v6h6M12 7v5l3 2"/>',
    shield: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Z"/><path d="m8 12 3 3 5-6"/>',
    spark: '<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5L12 3Z"/>'
  };
  const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${shapes[name] || shapes.folder}</svg>`;
  document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });
  const $ = id => document.getElementById(id);
  const element = (tag, className, text) => {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text !== undefined) el.textContent = text;
    return el;
  };
  const descriptors = {
    videos: ['All videos', 'A home for every quiet moment. Upload, preview, and organize your local library.'],
    portrait: ['Portrait', 'Vertical videos for the fullscreen reels viewer.'],
    landscape: ['Landscape', 'Wide videos in your library. The current reels viewer plays portrait videos.'],
    prompts: ['Text prompts', 'Gentle reminders that appear between the videos.'],
    trash: ['Recently removed', 'Kept on this computer, excluded from the next APK. Restore them whenever you like.']
  };
  let state, folder = 'videos', selected = new Set(), editing = null, removing = null, busy = false;
  let layout = 'grid', toastTimer, dragDepth = 0;
  const duration = seconds => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;
  const bytes = n => n >= 1e9 ? `${(n / 1e9).toFixed(2)} GB` : n >= 1e6 ? `${(n / 1e6).toFixed(1)} MB` : `${Math.ceil(n / 1000)} KB`;
  const orientation = video => video.orientation || (video.aspectRatio < 1 ? 'portrait' : 'landscape');
  const kind = () => folder === 'prompts' ? 'prompt' : 'video';
  function toast(text, error = false) {
    clearTimeout(toastTimer);
    $('toast').textContent = text;
    $('toast').classList.toggle('error', error);
    $('toast').hidden = false;
    toastTimer = setTimeout(() => { $('toast').hidden = true; }, 4500);
  }
  async function api(path, body) {
    const response = await fetch(path, body === undefined ? { cache: 'no-store' } : {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Calm-Admin': '1' }, body: JSON.stringify(body)
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'The change could not be saved.');
    return data;
  }
  async function refresh() {
    state = await api('/api/state');
    $('error-banner').hidden = true;
    render();
  }
  function rows() {
    if (!state) return [];
    let all = folder === 'prompts' ? state.prompts : folder === 'trash' ? state.trash : state.videos;
    if (folder === 'portrait' || folder === 'landscape') all = all.filter(v => orientation(v) === folder);
    const query = $('search').value.trim().toLowerCase();
    all = all.filter(row => {
      const entry = folder === 'trash' ? row.entry : row;
      return `${entry.title || entry.line || ''} ${entry.originalName || ''} ${entry.id}`.toLowerCase().includes(query);
    });
    return [...all].sort((a, b) => {
      const left = folder === 'trash' ? a.entry : a, right = folder === 'trash' ? b.entry : b;
      if ($('sort').value === 'recent') return String(b.removedAt || right.addedAt || right.id).localeCompare(String(a.removedAt || left.addedAt || left.id));
      if ($('sort').value === 'duration') return (right.durationSeconds || 0) - (left.durationSeconds || 0);
      return (left.title || left.line || '').localeCompare(right.title || right.line || '');
    });
  }
  function render() {
    if (!state) return;
    const counts = { videos: state.videos.length, portrait: state.videos.filter(v => orientation(v) === 'portrait').length, landscape: state.videos.filter(v => orientation(v) === 'landscape').length, prompts: state.prompts.length, trash: state.trash.length };
    for (const [key, value] of Object.entries(counts)) $(`count-${key}`).textContent = value;
    $('project-path').textContent = state.root;
    $('folder-title').textContent = descriptors[folder][0];
    $('breadcrumb-folder').textContent = descriptors[folder][0];
    $('folder-description').textContent = descriptors[folder][1];
    document.querySelectorAll('[data-folder]').forEach(el => { el.classList.toggle('active', el.dataset.folder === folder); el.setAttribute('aria-current', el.dataset.folder === folder ? 'page' : 'false'); });
    const promptFolder = folder === 'prompts', trashFolder = folder === 'trash';
    $('upload-button').hidden = trashFolder;
    $('new-prompt').hidden = !promptFolder;
    $('upload-label').textContent = promptFolder ? 'Import prompts' : 'Upload videos';
    $('prompt-settings').hidden = !promptFolder;
    $('prompt-interval').value = state.promptEvery;
    $('summary-count').textContent = `${counts[folder]} ${promptFolder ? 'prompts' : trashFolder ? 'removed items' : 'videos'}`;
    const totalBytes = state.videos.filter(v => folder === 'videos' || orientation(v) === folder).reduce((sum, v) => sum + v.byteSize, 0);
    $('summary-detail').textContent = promptFolder ? state.prompts.length ? `A prompt after every ${state.promptEvery} videos` : 'No prompts will appear in the viewer' : trashFolder ? 'Not included in the APK' : `${bytes(totalBytes)} in local files`;
    $('search').placeholder = promptFolder ? 'Search your prompts…' : trashFolder ? 'Search removed items…' : 'Search your videos…';
    $('footer-note').textContent = trashFolder ? 'Recently removed files stay outside the APK assets folder and are ignored by Git.' : promptFolder ? 'The app and viewer both read this prompt collection.' : 'These files become the offline video library in your next APK.';
    const visible = rows();
    const existing = new Set(visible.map(v => v.id));
    selected = new Set([...selected].filter(id => existing.has(id)));
    $('file-grid').classList.toggle('list', layout === 'list');
    $('file-grid').replaceChildren(...visible.map(card));
    $('empty-state').hidden = visible.length > 0;
    $('empty-title').textContent = $('search').value ? 'No matching files' : trashFolder ? 'Nothing in Recently removed' : promptFolder ? 'Make room for a quiet pause' : 'A little room for something new';
    $('empty-description').textContent = $('search').value ? 'Try a different name or clear your search.' : trashFolder ? 'Removed videos and prompts will appear here.' : promptFolder ? 'Choose New prompt, or import a TXT file with one prompt per line.' : 'Drop videos here or choose Upload videos.';
    $('visible-count').textContent = `${visible.length} items shown`;
    renderSelection();
  }
  function renderSelection() {
    $('selection-bar').hidden = selected.size === 0;
    $('selection-count').textContent = `${selected.size} selected`;
    $('select-all').checked = rows().length > 0 && selected.size === rows().length;
    $('select-all').indeterminate = selected.size > 0 && selected.size < rows().length;
    $('remove-selected').hidden = folder === 'trash';
    $('restore-selected').hidden = folder !== 'trash';
    document.querySelectorAll('.file-card').forEach(el => {
      const active = selected.has(el.dataset.id);
      el.classList.toggle('selected', active);
      el.querySelector('input[type=checkbox]').checked = active;
    });
  }
  function card(row) {
    const trash = folder === 'trash', entry = trash ? row.entry : row;
    const isPrompt = trash ? row.kind === 'prompt' : folder === 'prompts';
    const name = isPrompt ? entry.line : entry.title || entry.id;
    const tile = element('article', `file-card${isPrompt ? ' prompt-card' : ''}`);
    tile.dataset.id = row.id;
    const checkLabel = element('label', 'card-selection');
    const checkbox = element('input'); checkbox.type = 'checkbox'; checkbox.setAttribute('aria-label', `Select ${name}`);
    checkbox.checked = selected.has(row.id);
    checkbox.addEventListener('change', () => { if (checkbox.checked) selected.add(row.id); else selected.delete(row.id); renderSelection(); });
    checkLabel.append(checkbox);
    const thumbnail = element('button', 'card-thumbnail'); thumbnail.type = 'button'; thumbnail.setAttribute('aria-label', `${trash ? 'Restore' : isPrompt ? 'Edit' : 'Preview'} ${name}`);
    if (isPrompt) { thumbnail.innerHTML = icon('text'); thumbnail.append(element('span', 'prompt-snippet', entry.line)); }
    else if (!trash && entry.posterAssetPath) {
      const img = element('img'); img.src = `/${entry.posterAssetPath}`; img.alt = ''; img.loading = 'lazy';
      thumbnail.append(img);
      const marker = element('span', 'play-marker'); marker.innerHTML = icon('play'); thumbnail.append(marker);
      thumbnail.append(element('span', 'duration', duration(entry.durationSeconds)));
    } else { thumbnail.innerHTML = icon('portrait'); }
    const open = () => trash ? restore([row.id]) : openEditor(isPrompt ? 'prompt' : 'video', entry);
    thumbnail.addEventListener('click', open);
    const body = element('div', 'card-body');
    const title = element('button', 'card-name', name); title.title = name; title.addEventListener('click', open);
    const meta = element('div', 'card-meta', isPrompt ? 'Text prompt · Between reels' : `${orientation(entry) === 'portrait' ? 'Portrait' : 'Landscape'} · ${trash ? duration(entry.durationSeconds) : bytes(entry.byteSize)}`);
    const menu = element('button', 'card-menu'); menu.innerHTML = icon(trash ? 'restore' : 'more'); menu.setAttribute('aria-label', `${trash ? 'Restore' : 'Details for'} ${name}`); menu.addEventListener('click', open);
    body.append(title, meta, menu);
    if (trash) { const button = element('button', 'restore-card'); button.innerHTML = icon('restore'); button.append(document.createTextNode('Restore')); button.addEventListener('click', open); body.append(button); }
    tile.append(checkLabel, thumbnail, body);
    return tile;
  }
  function changeFolder(next) { folder = next; selected.clear(); $('search').value = ''; render(); }
  document.querySelectorAll('[data-folder]').forEach(el => el.addEventListener('click', () => changeFolder(el.dataset.folder)));
  $('search').addEventListener('input', render);
  $('sort').addEventListener('change', render);
  function setLayout(value) { layout = value; $('grid-view').classList.toggle('active', value === 'grid'); $('list-view').classList.toggle('active', value === 'list'); render(); }
  $('grid-view').addEventListener('click', () => setLayout('grid'));
  $('list-view').addEventListener('click', () => setLayout('list'));
  $('select-all').addEventListener('change', event => { selected = event.target.checked ? new Set(rows().map(row => row.id)) : new Set(); renderSelection(); });
  $('clear-selection').addEventListener('click', () => { selected.clear(); renderSelection(); });
  function openEditor(type, entry = null) {
    editing = { type, entry };
    $('editor-title').textContent = type === 'video' ? 'Video details' : entry ? 'Edit prompt' : 'New prompt';
    $('video-preview').hidden = type !== 'video'; $('video-details').hidden = type !== 'video'; $('name-label').hidden = type !== 'video'; $('prompt-label').hidden = type !== 'prompt';
    $('editor-error').hidden = true;
    $('editor-remove').hidden = !entry;
    $('save-editor').textContent = entry ? 'Save changes' : 'Add prompt';
    if (type === 'video') {
      $('preview-video').src = `/${entry.assetPath}`;
      $('preview-video').poster = entry.posterAssetPath ? `/${entry.posterAssetPath}` : '';
      $('video-name').value = entry.title || '';
      $('video-details').textContent = `${entry.width} × ${entry.height} · ${duration(entry.durationSeconds)} · ${bytes(entry.byteSize)} · ${entry.hasAudio ? 'With audio' : 'Silent'}\n${entry.filename}`;
    } else $('prompt-text').value = entry?.line || '';
    $('editor').showModal();
    if (type === 'prompt') $('prompt-text').focus();
  }
  function closeEditor() { $('editor').close(); $('preview-video').pause(); $('preview-video').removeAttribute('src'); $('preview-video').load(); editing = null; }
  $('editor').addEventListener('cancel', event => { event.preventDefault(); closeEditor(); });
  $('close-editor').addEventListener('click', closeEditor); $('cancel-editor').addEventListener('click', closeEditor);
  $('new-prompt').addEventListener('click', () => openEditor('prompt'));
  $('editor-form').addEventListener('submit', async event => {
    event.preventDefault(); if (!editing) return;
    $('save-editor').disabled = true;
    try {
      if (editing.type === 'prompt') await api('/api/prompts/save', { id: editing.entry?.id, line: $('prompt-text').value });
      else await api('/api/videos/rename', { id: editing.entry.id, title: $('video-name').value });
      closeEditor(); await refresh(); toast('Saved to your local library.');
    } catch (error) { $('editor-error').textContent = error.message; $('editor-error').hidden = false; }
    finally { $('save-editor').disabled = false; }
  });
  function confirmRemove(type, ids) {
    removing = { kind: type, ids };
    $('remove-message').textContent = `${ids.length} ${type === 'video' ? 'video' : 'prompt'}${ids.length === 1 ? '' : 's'} will move to Recently removed. They won’t be included in your next build. You can restore them here later.`;
    $('confirm-remove').showModal();
  }
  $('editor-remove').addEventListener('click', () => { const { type, entry } = editing; closeEditor(); confirmRemove(type, [entry.id]); });
  $('remove-selected').addEventListener('click', () => confirmRemove(kind(), [...selected]));
  $('cancel-remove').addEventListener('click', () => $('confirm-remove').close());
  $('confirm-remove-button').addEventListener('click', async () => {
    $('confirm-remove-button').disabled = true;
    try { const result = await api('/api/remove', removing); $('confirm-remove').close(); selected.clear(); await refresh(); toast(`${result.count} items moved to Recently removed.`); }
    catch (error) { $('confirm-remove').close(); toast(error.message, true); }
    finally { $('confirm-remove-button').disabled = false; }
  });
  async function restore(ids) {
    try { const result = await api('/api/restore', { ids }); selected.clear(); await refresh(); toast(`${result.count} items restored to the library.`); }
    catch (error) { toast(error.message, true); }
  }
  $('restore-selected').addEventListener('click', () => restore([...selected]));
  $('save-interval').addEventListener('click', async () => {
    try { await api('/api/settings', { promptEvery: Number($('prompt-interval').value) }); await refresh(); toast('Prompt spacing saved.'); }
    catch (error) { toast(error.message, true); }
  });
  $('upload-button').addEventListener('click', () => $(folder === 'prompts' ? 'prompt-input' : 'video-input').click());
  function uploadVideo(file) {
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest();
      request.open('POST', `/api/videos/upload?name=${encodeURIComponent(file.name)}`);
      request.setRequestHeader('X-Calm-Admin', '1');
      request.setRequestHeader('Content-Type', 'application/octet-stream');
      request.upload.addEventListener('progress', event => {
        if (event.lengthComputable) { $('upload-meter').value = event.loaded / event.total * 100; if (event.loaded === event.total) $('upload-detail').textContent = 'Preparing the offline video and thumbnail…'; }
      });
      request.addEventListener('load', () => { try { const result = JSON.parse(request.responseText); if (request.status >= 200 && request.status < 300) resolve(result); else reject(new Error(result.error)); } catch (_) { reject(new Error('The upload did not finish. Try again.')); } });
      request.addEventListener('error', () => reject(new Error('The local server could not be reached.')));
      request.send(file);
    });
  }
  async function uploadFiles(files) {
    if (busy || !files.length) return;
    busy = true; $('upload-button').disabled = true; $('upload-progress').hidden = false;
    const errors = []; let completed = 0;
    for (const [index, file] of [...files].entries()) {
      $('upload-status').textContent = `${index + 1} of ${files.length} · ${file.name}`;
      $('upload-detail').textContent = 'Saving your upload to this computer…'; $('upload-meter').value = 0;
      try {
        if (/\.(txt|json)$/i.test(file.name)) {
          if (file.size > 2 * 1024 * 1024) throw new Error('Prompt files must be smaller than 2 MB.');
          await api('/api/prompts/import', { name: file.name, text: await file.text() });
        } else await uploadVideo(file);
        completed += 1;
      } catch (error) { errors.push(`${file.name}: ${error.message}`); }
    }
    busy = false; $('upload-button').disabled = false; $('upload-progress').hidden = true;
    try { await refresh(); } catch (error) { errors.push(error.message); }
    if (errors.length) { $('error-banner').textContent = errors.join(' · '); $('error-banner').hidden = false; }
    if (completed) toast(`${completed} file${completed === 1 ? '' : 's'} added to your library.`);
  }
  for (const id of ['video-input', 'prompt-input']) $(id).addEventListener('change', async event => { await uploadFiles(event.target.files); event.target.value = ''; });
  document.addEventListener('dragenter', event => { if (event.dataTransfer?.types.includes('Files')) { event.preventDefault(); dragDepth += 1; $('drop-overlay').hidden = false; } });
  document.addEventListener('dragover', event => { if (event.dataTransfer?.types.includes('Files')) event.preventDefault(); });
  document.addEventListener('dragleave', event => { event.preventDefault(); dragDepth -= 1; if (dragDepth <= 0) { dragDepth = 0; $('drop-overlay').hidden = true; } });
  document.addEventListener('drop', event => { event.preventDefault(); dragDepth = 0; $('drop-overlay').hidden = true; uploadFiles(event.dataTransfer?.files || []); });
  refresh().catch(error => { $('error-banner').textContent = `${error.message} Start the local admin server, then refresh this page.`; $('error-banner').hidden = false; });
})();
