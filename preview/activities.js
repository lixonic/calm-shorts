(() => {
  'use strict';
  const hexColor = (hue, saturation, lightness) => {
    const a = saturation * Math.min(lightness, 1 - lightness);
    const component = n => {
      const k = (n + hue / 30) % 12;
      return Math.round(255 * (lightness - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))));
    };
    return '#' + [component(0), component(8), component(4)].map(n => n.toString(16).padStart(2, '0')).join('');
  };
  class AuroraColors {
    constructor() { this.used = new Set(); }
    next() {
      const hue = 135 + Math.random() * 165;
      return Array.from({length:3}, (_, index) => {
        let color;
        do {
          color = hexColor(135 + (hue - 135 + index * 47 + Math.random() * 12) % 165,
            0.36 + Math.random() * 0.16, 0.10 + index * 0.085 + Math.random() * 0.025);
        } while (this.used.has(color));
        this.used.add(color);
        return color;
      });
    }
  }
  const moment = (prompt, aurora) => ({type:'prompt', prompt, colors:aurora.next(), count:1 + Math.floor(Math.random() * 5)});
  function fingers(count) {
    const tops = [25,12,20,37];
    let parts = '';
    for (let finger = 0; finger < 4; finger++) {
      if (finger < count) parts += `<rect x="${29 + finger * 14}" y="${tops[finger]}" width="12" height="${87 - tops[finger]}" rx="7"/>`;
    }
    if (count === 5) parts += '<rect x="12" y="50" width="17" height="51" rx="8" transform="rotate(-37 19 70)"/>';
    parts += '<rect x="27" y="69" width="60" height="49" rx="17"/>';
    for (let finger = count; finger < 4; finger++) parts += `<rect x="${29 + finger * 14}" y="74" width="12" height="21" rx="6"/>`;
    if (count < 5) parts += '<path d="M29 83Q51 78 56 96" fill="none"/>';
    parts += '<path d="M46 107H66" fill="none"/>';
    return `<svg class="finger-cue" viewBox="0 0 110 130" role="img" aria-label="${count} ${count === 1 ? 'finger' : 'fingers'} held up"><g fill="#e8d8c4" stroke="#aa9680" stroke-width="1.6">${parts}</g></svg>`;
  }
  function shapes(count, kind) {
    const path = kind === 'stars'
      ? '<path d="m12 2 3.1 6.4 7 .9-5.1 5 1.2 7-6.2-3.3-6.2 3.3 1.2-7-5.1-5 7-.9Z"/>'
      : '<path d="M20 3C9 3 3 7 3 13c0 5 5 8 9 5 7-4 8-11 8-15Z"/><path d="M3 21 15 9" fill="none" stroke="#789281" stroke-width="1.2"/>';
    return `<div class="shape-cues" role="img" aria-label="${count} ${kind === 'stars' ? (count === 1 ? 'star' : 'stars') : (count === 1 ? 'leaf' : 'leaves')}">${Array.from({length:count}, () => `<svg viewBox="0 0 24 24" aria-hidden="true" fill="#e8ebdf">${path}</svg>`).join('')}</div>`;
  }
  window.CalmPromptDesign = Object.freeze({AuroraColors, moment, fingers, shapes});
})();
