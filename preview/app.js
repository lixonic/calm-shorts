(() => {
  'use strict';

  // A shuffle bag draws each member once. History is independent of the bag:
  // revisiting a video never consumes a new position in the current round.
  class RoundRobinPool {
    constructor(videos) {
      this.videos = videos;
      this.bag = [];
      this.round = 0;
      this.drawn = 0;
      this.lastDrawnId = null;
      this.history = [];
      this.historyIndex = -1;
    }

    shuffle() {
      this.bag = [...this.videos];
      for (let index = this.bag.length - 1; index > 0; index -= 1) {
        const swapIndex = Math.floor(Math.random() * (index + 1));
        [this.bag[index], this.bag[swapIndex]] = [this.bag[swapIndex], this.bag[index]];
      }
      // draw() uses shift(), so keep the first draw different from the final
      // draw in the preceding round whenever the pool has more than one video.
      if (this.bag.length > 1 && this.bag[0].id === this.lastDrawnId) {
        const swapIndex = 1 + Math.floor(Math.random() * (this.bag.length - 1));
        [this.bag[0], this.bag[swapIndex]] = [this.bag[swapIndex], this.bag[0]];
      }
      this.round += 1;
      this.drawn = 0;
    }

    next() {
      if (!this.videos.length) return null;
      if (this.historyIndex < this.history.length - 1) {
        this.historyIndex += 1;
        return this.current;
      }
      if (!this.bag.length) this.shuffle();
      const video = this.bag.shift();
      this.drawn += 1;
      this.lastDrawnId = video.id;
      this.history.push({ video, round: this.round, position: this.drawn });
      this.historyIndex = this.history.length - 1;
      return this.current;
    }

    previous() {
      if (this.historyIndex > 0) this.historyIndex -= 1;
      return this.current;
    }

    get current() { return this.history[this.historyIndex] || null; }
  }

  const byId = id => document.getElementById(id);
  const viewer = byId('viewer');
  const video = byId('reel-video');
  const loading = byId('loading-state');
  const mediaMessage = byId('media-message');
  const playPrompt = byId('play-prompt');
  const pauseButton = byId('pause-button');
  const soundButton = byId('sound-button');
  const aboutPanel = byId('about-panel');
  const pools = new Map();
  let orientation = 'portrait';
  let explicitPaused = false;
  let muted = true;
  let aboutOpen = false;
  let playBlocked = false;
  let loadingGeneration = 0;
  let feedbackTimer;
  let toastTimer;
  let skipTimer;
  let errorCount = 0;
  let pointerStart = null;
  let wheelLocked = false;
  let requestPlayGeneration = 0;
  let lastFocusBeforeAbout;

  const pool = () => pools.get(orientation);
  const currentEntry = () => pool()?.current;
  const shouldPause = () => explicitPaused || document.hidden || aboutOpen;

  // Exposes facts from the live queue and player for preview verification.
  // It cannot mutate playback or substitute a simulated media state.
  Object.defineProperty(window, 'calmPreviewState', {
    configurable: false,
    get: () => Object.freeze({
      currentId: currentEntry()?.video.id || null,
      round: currentEntry()?.round || 0,
      visitedCount: pool()?.drawn || 0,
      position: currentEntry()?.position || 0,
      orientation,
      paused: video.paused,
      explicitPaused,
      muted: video.muted,
      historyIndex: pool()?.historyIndex ?? -1,
      historyLength: pool()?.history.length || 0,
      libraryCounts: Object.freeze({ portrait: pools.get('portrait')?.videos.length || 0, landscape: pools.get('landscape')?.videos.length || 0 }),
      readyState: video.readyState,
      currentTime: video.currentTime,
      duration: Number.isFinite(video.duration) ? video.duration : null,
      error: video.error?.code || null
    })
  });

  function announce(text) {
    byId('reel-announcement').textContent = text;
  }

  function showToast(text) {
    clearTimeout(toastTimer);
    byId('toast').textContent = text;
    byId('toast').classList.add('visible');
    toastTimer = setTimeout(() => byId('toast').classList.remove('visible'), 2400);
  }

  function updateControls() {
    const paused = explicitPaused || playBlocked;
    pauseButton.setAttribute('aria-label', paused ? 'Play video' : 'Pause video');
    pauseButton.setAttribute('aria-pressed', String(paused));
    byId('pause-icon').innerHTML = paused
      ? '<path d="m9 5 10 7-10 7V5Z" fill="currentColor"/>'
      : '<path d="M8 5v14M16 5v14" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>';
    soundButton.setAttribute('aria-label', muted ? 'Turn sound on' : 'Turn sound off');
    soundButton.setAttribute('aria-pressed', String(!muted));
    byId('sound-icon').innerHTML = '<path d="M4 9v6h4l5 4V5L8 9H4Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/>' + (muted
      ? '<path d="m17 9 5 6m0-6-5 6" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>'
      : '<path d="M17 8.5a5 5 0 0 1 0 7M20 5.5a9 9 0 0 1 0 13" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>');
    byId('previous-button').disabled = !pool() || pool().historyIndex <= 0;
    playPrompt.hidden = !playBlocked || shouldPause() || !mediaMessage.hidden;
  }

  async function syncPlayback() {
    const playGeneration = ++requestPlayGeneration;
    video.muted = muted;
    if (shouldPause() || !currentEntry() || !mediaMessage.hidden) {
      video.pause();
      updateControls();
      return;
    }
    // A clip may finish just as the page is hidden. Returning to the viewer
    // continues the queue instead of replaying that completed clip.
    if (video.ended) {
      next();
      return;
    }
    try {
      await video.play();
      if (playGeneration !== requestPlayGeneration) return;
      playBlocked = false;
    } catch (error) {
      if (playGeneration !== requestPlayGeneration || error.name === 'AbortError') return;
      // Autoplay restrictions are recoverable with one tap, without showing
      // an error or turning a browser policy into a missing-media warning.
      if (error.name === 'NotAllowedError') {
        playBlocked = true;
        loading.hidden = true;
      }
    }
    updateControls();
  }

  function showEntry(entry) {
    if (!entry) {
      video.pause();
      loading.hidden = true;
      mediaMessage.hidden = false;
      byId('message-text').textContent = 'No little moments in this view yet.';
      byId('retry-button').hidden = true;
      byId('skip-button').hidden = true;
      byId('round-count').textContent = 'Choose another view';
      updateControls();
      return;
    }
    clearTimeout(skipTimer);
    loadingGeneration += 1;
    requestPlayGeneration += 1;
    video.pause();
    playBlocked = false;
    loading.hidden = false;
    mediaMessage.hidden = true;
    playPrompt.hidden = true;
    byId('retry-button').hidden = false;
    byId('skip-button').hidden = false;
    const { video: item, round, position } = entry;
    video.setAttribute('aria-label', `${orientation} video`);
    video.poster = item.posterAssetPath ? new URL(`../${item.posterAssetPath}`, location.href).href : '';
    video.src = new URL(`../${item.assetPath}`, location.href).href;
    video.dataset.generation = String(loadingGeneration);
    video.muted = muted;
    byId('round-count').textContent = `${String(position).padStart(2, '0')} / ${pool().videos.length}  ·  ROUND ${round}`;
    byId('progress-fill').style.transform = 'scaleX(0)';
    byId('playback-progress').setAttribute('aria-valuenow', '0');
    announce(`${orientation} video ${position} of ${pool().videos.length}.`);
    video.load();
    updateControls();
    syncPlayback();
  }

  function next() {
    if (aboutOpen || !pool()?.videos.length) return;
    explicitPaused = false;
    showEntry(pool().next());
  }

  function previous() {
    if (aboutOpen || !pool()?.videos.length) return;
    if (pool().historyIndex <= 0) {
      showToast('Your wandering starts here. Swipe up for the next moment.');
      return;
    }
    explicitPaused = false;
    showEntry(pool().previous());
  }

  function changeOrientation(nextOrientation) {
    if (orientation === nextOrientation) return;
    orientation = nextOrientation;
    explicitPaused = false;
    errorCount = 0;
    for (const button of document.querySelectorAll('.aspect-tab')) {
      const selected = button.dataset.orientation === orientation;
      button.classList.toggle('is-selected', selected);
      button.setAttribute('aria-pressed', String(selected));
    }
    showEntry(pool()?.current || pool()?.next());
  }

  function togglePaused(showFeedback = false) {
    if (!currentEntry() || !mediaMessage.hidden) return;
    explicitPaused = playBlocked ? false : !explicitPaused;
    playBlocked = false;
    if (showFeedback) {
      clearTimeout(feedbackTimer);
      byId('feedback-path').setAttribute('d', explicitPaused ? 'M8 5v14M16 5v14' : 'm9 5 10 7-10 7V5Z');
      byId('feedback-path').setAttribute('fill', explicitPaused ? 'none' : 'currentColor');
      byId('tap-feedback').classList.add('visible');
      feedbackTimer = setTimeout(() => byId('tap-feedback').classList.remove('visible'), 500);
    }
    syncPlayback();
  }

  function setAbout(open) {
    aboutOpen = open;
    aboutPanel.hidden = !open;
    byId('info-button').setAttribute('aria-expanded', String(open));
    if (open) {
      lastFocusBeforeAbout = document.activeElement;
      byId('close-about').focus();
    } else if (lastFocusBeforeAbout instanceof HTMLElement) {
      lastFocusBeforeAbout.focus();
    }
    syncPlayback();
  }

  video.addEventListener('playing', () => {
    loading.hidden = true;
    playBlocked = false;
    errorCount = 0;
    updateControls();
  });
  video.addEventListener('loadeddata', () => {
    loading.hidden = true;
    if (shouldPause()) video.pause();
  });
  video.addEventListener('waiting', () => {
    if (!video.error && !shouldPause() && !playBlocked) loading.hidden = false;
  });
  video.addEventListener('canplay', () => {
    loading.hidden = true;
    if (shouldPause()) video.pause();
  });
  video.addEventListener('ended', () => {
    if (!shouldPause()) next();
  });
  video.addEventListener('timeupdate', () => {
    const fraction = Number.isFinite(video.duration) && video.duration > 0 ? Math.min(1, video.currentTime / video.duration) : 0;
    byId('progress-fill').style.transform = `scaleX(${fraction})`;
    byId('playback-progress').setAttribute('aria-valuenow', String(Math.round(fraction * 100)));
  });
  video.addEventListener('error', () => {
    if (!currentEntry()) return;
    loading.hidden = true;
    errorCount += 1;
    // Keep the viewer moving past a broken clip, but stop after a complete
    // failed pass so an unavailable library cannot trigger an endless loop.
    const generation = loadingGeneration;
    if (errorCount < pool().videos.length && !shouldPause()) {
      showToast('This moment needs a little rest. Finding the next…');
      skipTimer = setTimeout(() => {
        if (generation !== loadingGeneration) return;
        if (!shouldPause()) next();
        else {
          mediaMessage.hidden = false;
          byId('message-text').textContent = 'This little moment couldn’t load.';
          updateControls();
        }
      }, 1400);
    } else {
      mediaMessage.hidden = false;
      byId('message-text').textContent = 'This little moment couldn’t load.';
      updateControls();
    }
  });

  byId('next-button').addEventListener('click', next);
  byId('previous-button').addEventListener('click', previous);
  pauseButton.addEventListener('click', () => togglePaused());
  playPrompt.addEventListener('click', () => { explicitPaused = false; playBlocked = false; syncPlayback(); });
  soundButton.addEventListener('click', () => { muted = !muted; video.muted = muted; updateControls(); if (!shouldPause()) syncPlayback(); });
  byId('retry-button').addEventListener('click', () => { errorCount = 0; showEntry(currentEntry()); });
  byId('skip-button').addEventListener('click', () => { errorCount = 0; next(); });
  byId('info-button').addEventListener('click', () => setAbout(true));
  byId('close-about').addEventListener('click', () => setAbout(false));
  byId('about-continue').addEventListener('click', () => setAbout(false));
  document.querySelectorAll('.aspect-tab').forEach(button => button.addEventListener('click', () => changeOrientation(button.dataset.orientation)));
  document.addEventListener('visibilitychange', syncPlayback);

  viewer.addEventListener('pointerdown', event => {
    if (aboutOpen || event.target.closest('button') || (event.pointerType === 'mouse' && event.button !== 0)) return;
    pointerStart = { x: event.clientX, y: event.clientY, id: event.pointerId };
    viewer.setPointerCapture(event.pointerId);
  });
  viewer.addEventListener('pointerup', event => {
    if (!pointerStart || pointerStart.id !== event.pointerId) return;
    const deltaX = event.clientX - pointerStart.x;
    const deltaY = event.clientY - pointerStart.y;
    pointerStart = null;
    if (Math.abs(deltaY) >= 45 && Math.abs(deltaY) > Math.abs(deltaX) * 1.3) {
      if (deltaY < 0) next(); else previous();
    } else if (Math.abs(deltaX) < 12 && Math.abs(deltaY) < 12) {
      togglePaused(true);
    }
  });
  viewer.addEventListener('pointercancel', () => { pointerStart = null; });
  viewer.addEventListener('wheel', event => {
    if (aboutOpen || Math.abs(event.deltaY) < 14) return;
    event.preventDefault();
    if (wheelLocked) return;
    wheelLocked = true;
    if (event.deltaY > 0) next(); else previous();
    setTimeout(() => { wheelLocked = false; }, 550);
  }, { passive: false });
  document.addEventListener('keydown', event => {
    if (aboutOpen) {
      if (event.key === 'Escape') { event.preventDefault(); setAbout(false); }
      if (event.key === 'Tab') {
        const first = byId('close-about');
        const last = byId('about-continue');
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
      }
      return;
    }
    if (event.key === 'ArrowUp' || event.key === 'ArrowRight') { event.preventDefault(); next(); }
    else if (event.key === 'ArrowDown' || event.key === 'ArrowLeft') { event.preventDefault(); previous(); }
    else if (event.code === 'Space' && !event.target.closest('button')) { event.preventDefault(); togglePaused(true); }
    else if (event.key.toLowerCase() === 'm') { muted = !muted; video.muted = muted; updateControls(); }
  });

  async function loadLibrary() {
    try {
      const response = await fetch(new URL('../assets/library.json', location.href), { cache: 'no-store' });
      if (!response.ok) throw new Error('Library unavailable');
      const library = await response.json();
      if (!Array.isArray(library.videos)) throw new Error('Invalid library');
      const distinctIds = new Set();
      const videos = library.videos.filter(item => {
        if (!item || typeof item.id !== 'string' || typeof item.assetPath !== 'string' || distinctIds.has(item.id)) return false;
        distinctIds.add(item.id);
        return true;
      }).map(item => ({ ...item, title: String(item.title || 'A little wonder'), orientation: item.orientation === 'landscape' || (item.orientation !== 'portrait' && item.width > item.height) ? 'landscape' : 'portrait' }));
      for (const aspect of ['portrait', 'landscape']) pools.set(aspect, new RoundRobinPool(videos.filter(item => item.orientation === aspect)));
      byId('library-counts').replaceChildren(...['portrait', 'landscape'].map(aspect => {
        const group = document.createElement('div');
        const count = document.createElement('strong');
        const label = document.createElement('span');
        count.textContent = String(pools.get(aspect).videos.length);
        label.textContent = `${aspect[0].toUpperCase()}${aspect.slice(1)} moments`;
        group.append(count, label);
        return group;
      }));
      if (!pools.get('portrait').videos.length && pools.get('landscape').videos.length) changeOrientation('landscape');
      else showEntry(pool().next());
    } catch (error) {
      loading.hidden = true;
      mediaMessage.hidden = false;
      byId('message-text').textContent = 'Our little world is still waking up.';
      byId('retry-button').hidden = true;
      byId('skip-button').hidden = true;
      byId('round-count').textContent = 'Come back in a moment';
      announce('The video collection is unavailable. Refresh to try again.');
    }
  }

  loadLibrary();
})();
