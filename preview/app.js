(() => {
  'use strict';

  const BREATH_PROMPTS = [
    'Take a slow, deep breath.',
    'Hold this breath for 10 seconds.',
    'Let the air leave you even more slowly.',
    'Breathe in gently through your nose.',
    'Soften your shoulders, then breathe.',
    'Hold a quiet breath for 8 seconds.',
    'Feel your belly rise with the next breath.',
    'Breathe out as if fogging a window.',
    'Take three tiny sips of air, then rest.',
    'Hold this breath for 6 seconds.',
    'Unclench your jaw and breathe out.',
    'Inhale for a count of four.',
    'Hold the breath, then smile as you let go.',
    'Breathe in calm. Breathe out hurry.',
    'Rest your hands. Take one long breath.',
    'Hold this breath for 10 seconds, then sigh.',
    'Notice the air at the tip of your nose.',
    'Breathe in for 4, out for 6.',
    'Let your next exhale last a little longer.',
    'Hold a gentle breath for 5 seconds.',
    'Drop your tongue from the roof of your mouth.',
    'Fill your lungs, then pause at the top.',
    'Breathe as if you have all the time you need.',
    'Take a deep breath into your back ribs.',
    'Hold this breath for 7 seconds.',
    'Blink slowly, then breathe out.',
    'Inhale warmth. Exhale the day so far.',
    'Let the next breath be quieter than the last.',
    'Place a hand on your chest and breathe.',
    'Hold this breath for 10 seconds, softly.',
    'Breathe in through the nose, out through the mouth.',
    'Count one long exhale all the way down.',
    'Relax your forehead. Take a deep breath.',
    'Hold the breath, then release it like a wave.',
    'Take up a little more air than usual, then rest.',
    'Breathe into the space between your shoulders.',
    'Hold a still breath for 4 seconds.',
    'Let your next inhale be round and easy.',
    'Exhale until the lungs feel empty, then wait.',
    'Take a deep breath and feel your feet.',
    'Hold this breath for 9 seconds.',
    'Breathe as if you are smelling something kind.',
    'Let the out-breath be twice as long.',
    'Close your eyes for one full breath.',
    'Hold the breath, then drip the air out slowly.',
    'Take a deep breath down to your belly.',
    'Pause after you exhale. Then begin again.',
    'Breathe in light. Breathe out tightness.',
    'Hold this breath for 10 seconds, then blink.',
    'One more slow breath, just because you can.'
  ];

  function shuffle(items, avoidFirst) {
    const bag = [...items];
    for (let index = bag.length - 1; index > 0; index -= 1) {
      const swapIndex = Math.floor(Math.random() * (index + 1));
      [bag[index], bag[swapIndex]] = [bag[swapIndex], bag[index]];
    }
    if (bag.length > 1 && avoidFirst && bag[0] === avoidFirst) {
      const swapIndex = 1 + Math.floor(Math.random() * (bag.length - 1));
      [bag[0], bag[swapIndex]] = [bag[swapIndex], bag[0]];
    }
    return bag;
  }

  class SessionFeed {
    constructor(videos, prompts = BREATH_PROMPTS, promptEvery = 5) {
      this.videos = shuffle(videos);
      this.items = [];
      this.historyIndex = -1;
      let promptBag = shuffle(prompts);
      let lastPrompt = null;
      this.videos.forEach((video, index) => {
        this.items.push({
          type: 'video',
          video,
          position: index + 1,
          total: this.videos.length
        });
        if ((index + 1) % promptEvery === 0) {
          if (!promptBag.length) promptBag = shuffle(prompts, lastPrompt);
          lastPrompt = promptBag.shift();
          this.items.push({ type: 'prompt', prompt: lastPrompt });
        }
      });
    }

    next() {
      if (this.historyIndex < this.items.length - 1) this.historyIndex += 1;
      return this.current;
    }

    previous() {
      if (this.historyIndex > 0) this.historyIndex -= 1;
      return this.current;
    }

    get current() { return this.items[this.historyIndex] || null; }
    get atEnd() { return this.historyIndex >= this.items.length - 1; }
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
  const breathPrompt = byId('breath-prompt');
  let feed = null;
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

  const currentEntry = () => feed?.current;
  const isPrompt = () => currentEntry()?.type === 'prompt';
  const shouldPause = () => explicitPaused || document.hidden || aboutOpen || isPrompt();

  Object.defineProperty(window, 'calmPreviewState', {
    configurable: false,
    get: () => Object.freeze({
      currentId: currentEntry()?.video?.id || null,
      prompt: currentEntry()?.prompt || null,
      visitedCount: currentEntry()?.position || 0,
      position: currentEntry()?.position || 0,
      paused: video.paused,
      explicitPaused,
      muted: video.muted,
      historyIndex: feed?.historyIndex ?? -1,
      historyLength: feed?.items.length || 0,
      libraryCounts: Object.freeze({ portrait: feed?.videos.length || 0, landscape: 0 }),
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
    const onPrompt = isPrompt();
    const paused = explicitPaused || playBlocked || onPrompt;
    pauseButton.hidden = onPrompt;
    soundButton.hidden = onPrompt;
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
    byId('previous-button').disabled = !feed || feed.historyIndex <= 0;
    byId('next-button').disabled = !feed || feed.atEnd;
    playPrompt.hidden = onPrompt || !playBlocked || shouldPause() || !mediaMessage.hidden;
  }

  async function syncPlayback() {
    const playGeneration = ++requestPlayGeneration;
    video.muted = muted;
    if (shouldPause() || !currentEntry() || currentEntry().type !== 'video' || !mediaMessage.hidden) {
      video.pause();
      updateControls();
      return;
    }
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
      breathPrompt.hidden = true;
      mediaMessage.hidden = false;
      byId('message-text').textContent = feed ? 'That is all for this wander.' : 'No little moments in this view yet.';
      byId('retry-button').hidden = true;
      byId('skip-button').hidden = true;
      byId('round-count').textContent = 'A quiet pause';
      updateControls();
      return;
    }
    clearTimeout(skipTimer);
    loadingGeneration += 1;
    requestPlayGeneration += 1;
    video.pause();
    playBlocked = false;
    mediaMessage.hidden = true;
    playPrompt.hidden = true;
    byId('retry-button').hidden = false;
    byId('skip-button').hidden = false;
    if (entry.type === 'prompt') {
      loading.hidden = true;
      breathPrompt.hidden = false;
      video.removeAttribute('src');
      video.load();
      byId('prompt-text').textContent = entry.prompt;
      byId('round-count').textContent = 'A breath';
      byId('progress-fill').style.transform = 'scaleX(0)';
      announce(entry.prompt);
      updateControls();
      return;
    }
    breathPrompt.hidden = true;
    loading.hidden = false;
    const { video: item, position, total } = entry;
    video.setAttribute('aria-label', 'Portrait video');
    video.poster = item.posterAssetPath ? new URL(`../${item.posterAssetPath}`, location.href).href : '';
    video.src = new URL(`../${item.assetPath}`, location.href).href;
    video.dataset.generation = String(loadingGeneration);
    video.muted = muted;
    byId('round-count').textContent = `${String(position).padStart(2, '0')} / ${total}`;
    byId('progress-fill').style.transform = 'scaleX(0)';
    byId('playback-progress').setAttribute('aria-valuenow', '0');
    announce(`Video ${position} of ${total}.`);
    video.load();
    updateControls();
    syncPlayback();
  }

  function next() {
    if (aboutOpen || !feed?.videos.length) return;
    if (feed.atEnd && feed.historyIndex >= 0) {
      showToast('That is all for this wander. Swipe down to revisit.');
      return;
    }
    explicitPaused = false;
    showEntry(feed.next());
  }

  function previous() {
    if (aboutOpen || !feed?.videos.length) return;
    if (feed.historyIndex <= 0) {
      showToast('Your wandering starts here. Swipe up for the next moment.');
      return;
    }
    explicitPaused = false;
    showEntry(feed.previous());
  }

  function togglePaused(showFeedback = false) {
    if (!currentEntry() || currentEntry().type !== 'video' || !mediaMessage.hidden) return;
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
    if (!currentEntry() || currentEntry().type !== 'video') return;
    loading.hidden = true;
    errorCount += 1;
    const generation = loadingGeneration;
    if (errorCount < feed.videos.length && !shouldPause()) {
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
  byId('prompt-continue').addEventListener('click', next);
  byId('info-button').addEventListener('click', () => setAbout(true));
  byId('close-about').addEventListener('click', () => setAbout(false));
  byId('about-continue').addEventListener('click', () => setAbout(false));
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
    } else if (Math.abs(deltaX) < 12 && Math.abs(deltaY) < 12 && !isPrompt()) {
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
        const landscape = item.orientation === 'landscape' || (item.orientation !== 'portrait' && item.width > item.height);
        return !landscape;
      }).map(item => ({ ...item, title: String(item.title || 'A little wonder') }));
      feed = new SessionFeed(videos);
      byId('library-counts').replaceChildren((() => {
        const group = document.createElement('div');
        const count = document.createElement('strong');
        const label = document.createElement('span');
        count.textContent = String(videos.length);
        label.textContent = 'Portrait moments';
        group.append(count, label);
        return group;
      })());
      showEntry(feed.next());
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
