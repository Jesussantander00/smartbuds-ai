// SmartBuds AI — versión web (iPhone o cualquier navegador).
// La música suena AQUÍ MISMO con el reproductor oficial de YouTube (insertado),
// se controla con botones o con la voz, y aprende tus gustos en tu cuenta de
// Supabase (la misma de la app de Android).
(() => {
  'use strict';
  const { SUPABASE_URL: SB, SUPABASE_ANON_KEY: KEY } = window.SMARTBUDS_CONFIG || {};
  const $ = (id) => document.getElementById(id);
  const IOS = /iphone|ipad|ipod/i.test(navigator.userAgent)
    || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const STANDALONE = window.navigator.standalone === true
    || matchMedia('(display-mode: standalone)').matches;
  // Mismos pesos que la app: completa +2, repetida +3, me gusta +5, saltada −2, no me gusta −5.
  const W = { completes: 2, repeats: 3, likes: 5, skips: -2, dislikes: -5 };
  const COMPLETE_MS = 90000;
  const SKIP_MS = 30000;

  // ================================================================ Estado
  let session = loadJSON('smartbuds.session');
  const tracks = new Map(); // track_key → fila de track_scores
  let queue = [];           // próximas canciones {title, artist}
  const history = [];       // canciones ya sonadas (para «Devuelve»)
  let current = null;       // {key, title, artist, videoId, startedAt}
  let player = null;
  let playerReady = false;
  let pendingVideo = null;
  let volume = 80;

  function loadJSON(k) { try { return JSON.parse(localStorage.getItem(k)); } catch { return null; } }
  function saveJSON(k, v) {
    try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, JSON.stringify(v)); } catch { /* modo privado */ }
  }
  const norm = (s) => String(s || '').toLowerCase().normalize('NFD')
    .replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9ñ ]/g, ' ').replace(/\s+/g, ' ').trim();
  const keyFor = (title, artist) => `${String(title).trim().toLowerCase()}|${String(artist || '').trim().toLowerCase()}`;
  const score = (r) => Object.entries(W).reduce((s, [k, w]) => s + (r[k] || 0) * w, 0);

  // ================================================================ Cuenta (Supabase Auth)
  async function auth(path, body) {
    const res = await fetch(`${SB}/auth/v1/${path}`, {
      method: 'POST',
      headers: { apikey: KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(friendly(json));
    return json;
  }

  function friendly(j) {
    const m = String(j.msg || j.error_description || j.message || '').toLowerCase();
    if (m.includes('invalid login') || m.includes('invalid credentials')) return 'Correo o contraseña incorrectos.';
    if (m.includes('already')) return 'Ese correo ya tiene cuenta. Toca «Entrar».';
    if (m.includes('not confirmed')) return 'Primero confirma tu correo (revisa tu bandeja).';
    if (m.includes('password')) return 'La contraseña debe tener al menos 6 caracteres.';
    if (m.includes('rate')) return 'Demasiados intentos. Espera un momento.';
    return 'No se pudo completar. Inténtalo otra vez.';
  }

  function keep(json) {
    session = {
      access: json.access_token,
      refresh: json.refresh_token,
      exp: Date.now() + (json.expires_in || 3600) * 1000,
      email: json.user?.email || session?.email,
      uid: json.user?.id || session?.uid,
    };
    saveJSON('smartbuds.session', session);
  }

  async function token() {
    if (!session) return null;
    if (Date.now() < session.exp - 120000) return session.access;
    try {
      keep(await auth('token?grant_type=refresh_token', { refresh_token: session.refresh }));
      return session.access;
    } catch {
      signOut();
      return null;
    }
  }

  function signOut() {
    session = null;
    saveJSON('smartbuds.session', null);
    tracks.clear();
    renderMusic();
  }

  async function rest(method, path, body, prefer) {
    const t = await token();
    if (!t) return null;
    const headers = { apikey: KEY, Authorization: `Bearer ${t}` };
    if (body) { headers['Content-Type'] = 'application/json'; headers.Prefer = prefer || 'return=minimal'; }
    const res = await fetch(`${SB}/rest/v1/${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
    if (!res.ok) throw new Error(`Supabase ${res.status}`);
    return method === 'GET' ? res.json() : null;
  }

  async function fetchTracks() {
    if (!session) return;
    try {
      const rows = await rest('GET',
        `track_scores?select=*&device_id=eq.${encodeURIComponent(`u:${session.uid}`)}&limit=2000`);
      tracks.clear();
      for (const r of rows || []) tracks.set(r.track_key, r);
      renderMusic();
    } catch { status('No pude traer tus canciones.'); }
  }

  // ================================================================ Aprender (igual que la app)
  function stats(t) {
    let row = tracks.get(t.key);
    if (!row) {
      row = { track_key: t.key, title: t.title, artist: t.artist || null,
              plays: 0, completes: 0, skips: 0, repeats: 0, likes: 0, dislikes: 0 };
      tracks.set(t.key, row);
    }
    return row;
  }

  function record(t, type) {
    if (!t) return;
    const row = stats(t);
    const field = { play: 'plays', complete: 'completes', skip: 'skips', repeat: 'repeats',
                    like: 'likes', dislike: 'dislikes' }[type];
    row[field] = (row[field] || 0) + 1;
    row.last_played_at = new Date().toISOString();
    renderMusic();
    if (!session) return; // sin cuenta: solo en esta visita
    const who = { device_id: `u:${session.uid}`, user_id: session.uid };
    rest('POST', 'listening_events', {
      ...who, track_key: t.key, title: t.title, artist: t.artist || null,
      app_package: 'web', event_type: type, happened_at: row.last_played_at,
    }).catch(() => {});
    rest('POST', 'track_scores?on_conflict=device_id,track_key', {
      ...who, track_key: row.track_key, title: row.title, artist: row.artist,
      plays: row.plays, completes: row.completes, skips: row.skips, repeats: row.repeats,
      likes: row.likes, dislikes: row.dislikes, last_played_at: row.last_played_at,
    }, 'resolution=merge-duplicates,return=minimal').catch(() => {});
  }

  /** Al dejar una canción: completa (≥90 s) o saltada (<30 s con «Cambia»). */
  function finishCurrent(skipped) {
    if (!current) return;
    const ms = Date.now() - current.startedAt;
    if (ms >= COMPLETE_MS) record(current, 'complete');
    else if (skipped && ms < SKIP_MS) record(current, 'skip');
  }

  const ranked = () => [...tracks.values()].map((r) => ({ ...r, s: score(r) }))
    .filter((r) => r.s > 0).sort((a, b) => b.s - a.s);

  function topArtists(n) {
    const by = {};
    for (const t of ranked()) if (t.artist) by[t.artist] = (by[t.artist] || 0) + t.s;
    return Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, n).map(([a]) => a);
  }

  // ================================================================ Reproductor (YouTube insertado)
  window.onYouTubeIframeAPIReady = () => {
    player = new YT.Player('player', {
      width: '100%',
      height: '100%',
      // Sin controles de YouTube ni pantalla completa ni videos sugeridos:
      // se maneja con los botones de SmartBuds y no te saca de la página.
      playerVars: {
        playsinline: 1, controls: 0, disablekb: 1, fs: 0, rel: 0,
        iv_load_policy: 3, modestbranding: 1, origin: location.origin,
      },
      events: {
        onReady: () => {
          playerReady = true;
          player.setVolume(volume);
          if (pendingVideo) { player.loadVideoById(pendingVideo); pendingVideo = null; }
        },
        onStateChange: (e) => {
          const isPlaying = e.data === YT.PlayerState.PLAYING;
          $('playBtn').textContent = isPlaying ? '⏸' : '▶';
          document.body.classList.toggle('is-playing', isPlaying); // ecualizador animado
          if (e.data === YT.PlayerState.ENDED) next(false);
        },
        onError: () => { status('Esa canción no se puede poner aquí. Paso a otra.'); next(false); },
      },
    });
  };
  const yt = document.createElement('script');
  yt.src = 'https://www.youtube.com/iframe_api';
  document.head.appendChild(yt);

  async function findVideo(query) {
    const res = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
    if (res.status === 503) throw new Error('La búsqueda aún no está activada (falta la clave en Vercel).');
    if (!res.ok) throw new Error('No pude buscar la canción.');
    const items = await res.json();
    if (!items.length) throw new Error(`No encontré «${query}».`);
    return items[0];
  }

  /** «Ojalá - Ryan Castro (Video Oficial)» → título y artista razonables. */
  function parseTitle(video) {
    const clean = video.title.replace(/\s*[([].*?(official|oficial|video|audio|lyric|letra|visualizer).*?[)\]]/gi, '').trim();
    const parts = clean.split(/\s+[-–—]\s+/);
    if (parts.length >= 2) return { artist: parts[0].trim(), title: parts.slice(1).join(' - ').trim() };
    return { title: clean, artist: video.channel.replace(/\s*-\s*Topic$/i, '').replace(/VEVO$/i, '').trim() };
  }

  // ================================================================ Apps de música del teléfono
  // Cada persona usa SU app (con su cuenta). SmartBuds elige la canción y la
  // abre allí; para «Cambia» vuelves a SmartBuds y abre la siguiente.
  const APPS = {
    here: { name: 'SmartBuds' },
    youtube: { name: 'YouTube Music' },
    spotify: { name: 'Spotify' },
    apple: { name: 'Apple Music' },
    amazon: { name: 'Amazon Music' },
    deezer: { name: 'Deezer' },
  };
  // Por defecto suena aquí mismo; abrir otra app es una opción.
  let target = loadJSON('smartbuds.target2') || 'here';
  if (!APPS[target]) target = 'here';

  // Apple (iTunes) también exige JSONP para pedirle datos desde otra página.
  function jsonp(url) {
    return new Promise((resolve, reject) => {
      const cb = `cb${Date.now()}${Math.floor(Math.random() * 1e6)}`;
      const s = document.createElement('script');
      const timer = setTimeout(() => { cleanup(); reject(new Error('timeout')); }, 7000);
      function cleanup() { clearTimeout(timer); delete window[cb]; s.remove(); }
      window[cb] = (data) => { cleanup(); resolve(data); };
      s.src = `${url}${url.includes('?') ? '&' : '?'}callback=${cb}`;
      s.onerror = () => { cleanup(); reject(new Error('jsonp')); };
      document.head.appendChild(s);
    });
  }

  /** Enlace que abre la canción en la app elegida (enlaces universales). */
  async function appLink(app, query) {
    const q = encodeURIComponent(query);
    switch (app) {
      case 'youtube': {
        try { return { url: `https://music.youtube.com/watch?v=${(await findVideo(query)).id}`, exact: true }; }
        catch { return { url: `https://music.youtube.com/search?q=${q}` }; }
      }
      case 'apple': {
        try {
          const r = await jsonp(`https://itunes.apple.com/search?term=${q}&entity=song&limit=1&country=co`);
          const t = r.results?.[0];
          if (t?.trackViewUrl) return { url: t.trackViewUrl, exact: true, title: t.trackName, artist: t.artistName };
        } catch { /* sin resultado: búsqueda */ }
        return { url: `https://music.apple.com/search?term=${q}` };
      }
      case 'deezer': {
        try {
          const r = await deezer(`/search?q=${q}&limit=1`);
          const t = r.data?.[0];
          if (t) return { url: `https://www.deezer.com/track/${t.id}`, exact: true, title: t.title, artist: t.artist?.name };
        } catch { /* sin resultado: búsqueda */ }
        return { url: `https://www.deezer.com/search/${q}` };
      }
      case 'spotify': return { url: `https://open.spotify.com/search/${q}` };
      case 'amazon': return { url: `https://music.amazon.com/search/${q}` };
      default: return null;
    }
  }

  function showOpenCard(url, label) {
    const a = $('openApp');
    a.href = url;
    a.textContent = `▶ Abrir en ${label}`;
    $('openCard').classList.remove('hidden');
  }

  /** Pone una canción {title, artist} o una búsqueda libre {query}. */
  async function play(item, { fromHistory = false, skipped = false } = {}) {
    status('Buscando…');
    try {
      const query = item.query || [item.title, item.artist].filter(Boolean).join(' ');
      let info;
      let videoId = null;
      if (target === 'here') {
        const video = await findVideo(query);
        videoId = video.id;
        info = item.title ? { title: item.title, artist: item.artist } : parseTitle(video);
      } else {
        const link = await appLink(target, query);
        info = item.title ? { title: item.title, artist: item.artist }
          : (link.title ? { title: link.title, artist: link.artist } : { title: query, artist: '' });
        showOpenCard(link.url, APPS[target].name);
        // Se abre la app (con la cuenta de cada persona). Si el teléfono no la
        // abre solo, queda el botón «Abrir en …» para tocarlo.
        setTimeout(() => { window.location.href = link.url; }, 150);
      }
      finishCurrent(skipped);
      if (current && !fromHistory) history.push({ title: current.title, artist: current.artist });
      current = { ...info, key: keyFor(info.title, info.artist), videoId, startedAt: Date.now() };
      if (videoId) {
        $('playerWrap').classList.remove('empty');
        $('openCard').classList.add('hidden');
        if (playerReady) player.loadVideoById(videoId); else pendingVideo = videoId;
      } else {
        $('playerWrap').classList.add('empty');
        if (playerReady) player.pauseVideo();
      }
      $('nowSource').textContent = `Sonando en ${APPS[target].name}`;
      $('nowTitle').textContent = [info.title, info.artist].filter(Boolean).join(' — ');
      record(current, 'play');
      status(target === 'here' ? '' : `Abriendo en ${APPS[target].name}. Vuelve aquí y toca ⏭ para la siguiente.`);
      if (target === 'here') say(`Reproduciendo ${info.title}`);
    } catch (e) {
      status(e.message);
      say('No pude ponerla.');
    }
  }

  // ================================================================ Órdenes
  async function next(skipped = true) {
    if (!queue.length) await refillQueue();
    const item = queue.shift();
    if (item) play(item, { skipped });
    else status('No tengo más canciones en la fila.');
  }

  function previous() {
    const item = history.pop();
    if (!item) { if (playerReady) player.seekTo(0, true); return; }
    if (current) queue.unshift({ title: current.title, artist: current.artist });
    play(item, { fromHistory: true });
    if (current) record({ ...item, key: keyFor(item.title, item.artist) }, 'repeat');
  }

  function toggle() {
    if (target !== 'here') {
      if (current) status('La pausa se hace en la app de música (o con el botón de tus audífonos).');
      else favorites();
      return;
    }
    if (!playerReady || !current) return favorites();
    const playing = player.getPlayerState() === YT.PlayerState.PLAYING;
    playing ? player.pauseVideo() : player.playVideo();
  }

  function setVol(delta) {
    if (target !== 'here') { status('El volumen se cambia con los botones del teléfono.'); return; }
    volume = Math.max(0, Math.min(100, volume + delta));
    if (playerReady) player.setVolume(volume);
    status(IOS ? 'En iPhone el volumen se cambia con los botones del teléfono.' : `Volumen ${volume}%`);
  }

  function like() {
    if (!current) return;
    record(current, 'like');
    say('Guardada en tus favoritas.');
    status('❤ Guardada en tus favoritas');
  }

  function dislike() {
    if (!current) return;
    record(current, 'dislike');
    say('Entendido, no te la vuelvo a poner.');
    next(false);
  }

  /** «Pon algo que me guste»: fila de favoritas al azar, las mejores con más probabilidad. */
  function favorites() {
    const good = ranked().slice(0, 25);
    if (!good.length) {
      status(session ? 'Aún estoy aprendiendo tus gustos. Busca algo y dime «Me gusta».'
                     : 'Entra con tu cuenta (en Mi música) para usar tus gustos.');
      say('Todavía estoy aprendiendo tus gustos.');
      return;
    }
    const bag = [...good];
    queue = [];
    while (bag.length) {
      const total = bag.reduce((s, t) => s + t.s, 0);
      let r = Math.random() * total;
      const i = Math.max(0, bag.findIndex((t) => (r -= t.s) <= 0));
      const [t] = bag.splice(i, 1);
      if (t.track_key !== current?.key) queue.push({ title: t.title, artist: t.artist });
    }
    next(false);
  }

  async function refillQueue() {
    // Sin fila: más de tus favoritas, o descubrir.
    const good = ranked().filter((t) => t.track_key !== current?.key).slice(0, 15);
    if (good.length) {
      queue = good.sort(() => Math.random() - 0.5).map((t) => ({ title: t.title, artist: t.artist }));
    } else {
      await discover(false);
    }
  }

  // Deezer no permite pedirle datos desde otra página con fetch; usa JSONP.
  function deezer(path) {
    return new Promise((resolve, reject) => {
      const cb = `dz${Date.now()}${Math.floor(Math.random() * 1e6)}`;
      const s = document.createElement('script');
      const timer = setTimeout(() => { cleanup(); reject(new Error('timeout')); }, 7000);
      function cleanup() { clearTimeout(timer); delete window[cb]; s.remove(); }
      window[cb] = (data) => { cleanup(); resolve(data); };
      s.src = `https://api.deezer.com${path}${path.includes('?') ? '&' : '?'}output=jsonp&callback=${cb}`;
      s.onerror = () => { cleanup(); reject(new Error('deezer')); };
      document.head.appendChild(s);
    });
  }

  /** «Pon algo nuevo»: canciones de artistas parecidos a tus favoritos. */
  async function discover(start = true) {
    const mine = topArtists(3);
    const seed = mine[Math.floor(Math.random() * mine.length)] || current?.artist;
    if (!seed) {
      queue = [{ query: 'exitos del momento' }];
      if (start) next(false);
      return;
    }
    status(`Buscando artistas parecidos a ${seed}…`);
    try {
      const found = await deezer(`/search/artist?q=${encodeURIComponent(seed)}&limit=1`);
      const id = found.data?.[0]?.id;
      const known = new Set([...tracks.values()].map((t) => norm(t.artist)));
      const related = ((await deezer(`/artist/${id}/related?limit=10`)).data || [])
        .filter((a) => !known.has(norm(a.name)))
        .sort(() => Math.random() - 0.5).slice(0, 4);
      const songs = [];
      for (const a of related) {
        const top = (await deezer(`/artist/${a.id}/top?limit=3`)).data || [];
        for (const t of top) songs.push({ title: t.title, artist: a.name });
      }
      queue = songs.sort(() => Math.random() - 0.5);
      if (!queue.length) queue = [{ query: `${seed} mix` }];
      if (start) { say(`Te pongo algo parecido a ${seed}.`); next(false); }
    } catch {
      queue = [{ query: `${seed} mix` }];
      if (start) next(false);
    }
  }

  const COMMANDS = {
    cambia: next, cambiala: next, cambiar: next, siguiente: next, pasa: next, salta: next,
    'otra cancion': next, 'siguiente cancion': next,
    devuelve: previous, devuelvela: previous, anterior: previous, regresa: previous,
    'cancion anterior': previous,
    pausa: () => current && playerReady && player.pauseVideo(), pausar: () => current && playerReady && player.pauseVideo(),
    detente: () => current && playerReady && player.pauseVideo(),
    continua: () => (current && playerReady ? player.playVideo() : favorites()),
    continuar: () => (current && playerReady ? player.playVideo() : favorites()),
    reanuda: () => current && playerReady && player.playVideo(),
    sube: () => setVol(15), 'sube el volumen': () => setVol(15), 'mas volumen': () => setVol(15),
    baja: () => setVol(-15), 'baja el volumen': () => setVol(-15), 'menos volumen': () => setVol(-15),
    'me gusta': like, 'me encanta': like, 'me gusta esta': like, 'me gusta esta cancion': like,
    'no me gusta': dislike, 'no me gusta esta': dislike, 'quita esta': dislike,
    'pon algo que me guste': favorites, 'algo que me guste': favorites, 'mis favoritas': favorites,
    'pon mis favoritas': favorites, 'pon mi musica': favorites,
    'pon algo nuevo': () => discover(), 'algo nuevo': () => discover(), sorprendeme: () => discover(),
    'descubre algo': () => discover(),
  };
  const MOODS = {
    entrenar: 'musica para entrenar', gym: 'musica para entrenar', ejercicio: 'musica para entrenar',
    tranquilo: 'musica tranquila relajante', tranquila: 'musica tranquila relajante', relajarme: 'musica tranquila relajante',
    fiesta: 'musica para bailar fiesta', bailar: 'musica para bailar fiesta', dormir: 'musica para dormir',
    estudiar: 'musica para estudiar concentracion', trabajar: 'musica para estudiar concentracion',
    romantico: 'canciones romanticas', romantica: 'canciones romanticas', triste: 'canciones tristes',
    alegre: 'musica alegre', feliz: 'musica alegre',
  };

  /**
   * Interpreta lo que dijiste. `free`: tocaste el micrófono, así que si no es
   * una orden se toma como el nombre de una canción. En escucha continua solo
   * cuentan las órdenes exactas (para que la música o una conversación no
   * disparen nada).
   */
  let awaitingSong = false; // después de «Busca», la siguiente frase es la canción

  function handleSpeech(said, free) {
    const n = norm(said);
    if (!n) return false;
    $('heard').textContent = `Oí: «${said}»`;
    if (awaitingSong) {
      awaitingSong = false;
      play({ query: said.replace(/^(la cancion|cancion)\s+/i, '') });
      return true;
    }
    if (['busca', 'buscar', 'buscame', 'busca una cancion'].includes(n)) {
      awaitingSong = true;
      say('¿Qué canción?');
      $('micStatus').textContent = '¿Qué canción? Dímela…';
      setTimeout(() => startListening(true), 1300); // tras la pregunta
      return true;
    }
    if (COMMANDS[n]) { COMMANDS[n](); return true; }
    const search = n.match(/^(busca|buscar|buscame|pon la cancion|reproduce)\s+(.+)$/);
    if (search) { play({ query: search[2] }); return true; }
    if (/^(pon|algo|quiero)\b/.test(n)) {
      const mood = n.split(' ').map((w) => MOODS[w]).find(Boolean);
      if (mood) { queue = []; play({ query: mood }); return true; }
      const artist = n.match(/^(pon algo de|pon musica de|pon canciones de|quiero escuchar a|pon)\s+(.+)$/);
      if (artist) { play({ query: artist[2] }); return true; }
    }
    if (free) { play({ query: said }); return true; }
    return false;
  }

  // ================================================================ Voz
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  let rec = null;
  let listening = false;
  let continuous = loadJSON('smartbuds.continuous') === true;
  let manual = false; // la escucha actual la inició un toque al micrófono

  function setupVoice() {
    if (!SR) {
      $('micStatus').textContent = IOS && STANDALONE
        ? 'En iPhone la voz no funciona desde el ícono de inicio. Ábrela en Safari para hablarle.'
        : 'Este navegador no permite la voz. Usa los botones o el buscador.';
      $('mic').disabled = true;
      $('continuous').disabled = true;
      return;
    }
    rec = new SR();
    rec.lang = 'es-CO';
    rec.interimResults = false;
    rec.maxAlternatives = 1;
    rec.onstart = () => { listening = true; renderMic(); };
    rec.onend = () => {
      listening = false;
      if (!awaitingSong) renderMic();
      if (continuous) setTimeout(startListening, 400); // sigue escuchando
    };
    rec.onerror = (e) => {
      if (e.error === 'not-allowed' || e.error === 'service-not-allowed') {
        continuous = false;
        $('continuous').checked = false;
        $('micStatus').textContent = STANDALONE && IOS
          ? 'En iPhone la voz no funciona desde el ícono de inicio. Ábrela en Safari para hablarle.'
          : 'Permite el micrófono para SmartBuds (Ajustes → Safari → Micrófono).';
      } else if (e.error === 'no-speech') {
        $('micStatus').textContent = 'No te escuché. Toca y habla otra vez.';
      } else if (e.error === 'audio-capture') {
        $('micStatus').textContent = 'Otra app está usando el micrófono.';
      } else {
        $('micStatus').textContent = `La voz falló (${e.error}). Toca y vuelve a intentar.`;
      }
      awaitingSong = false;
    };
    rec.onresult = (e) => {
      const res = e.results[e.results.length - 1];
      const said = res[0].transcript.trim();
      handleSpeech(said, manual);
      manual = false;
    };
  }

  function startListening(byTap = false) {
    if (!rec || listening) return;
    manual = byTap;
    rec.continuous = continuous && !IOS; // iPhone corta la escucha larga; se reinicia sola
    try { rec.start(); } catch { /* ya estaba escuchando */ }
  }

  function renderMic() {
    $('mic').classList.toggle('listening', listening);
    document.body.classList.toggle('is-listening', listening);
    $('micStatus').textContent = listening
      ? (continuous ? 'Escuchando… di «Cambia», «Pausa», «Busca …»' : 'Te escucho…')
      : 'Toca y di: «Cambia», «Pausa», «Sube», «Busca …»';
  }

  // Respuesta por voz (la del navegador).
  let speakBack = loadJSON('smartbuds.speakBack') !== false;
  function say(text) {
    if (!speakBack || !('speechSynthesis' in window)) return;
    try {
      const u = new SpeechSynthesisUtterance(text);
      u.lang = 'es-CO';
      speechSynthesis.cancel();
      speechSynthesis.speak(u);
    } catch { /* sin voz disponible */ }
  }

  // ================================================================ Pantalla
  function status(msg) { $('status').textContent = msg || ''; }

  function showTab(name) {
    for (const s of document.querySelectorAll('.tab')) s.classList.toggle('hidden', s.id !== `tab-${name}`);
    for (const b of document.querySelectorAll('.tabbar button')) b.classList.toggle('active', b.dataset.tab === name);
    $('title').textContent = { home: 'SmartBuds AI', assistant: 'Asistente', music: 'Mi música' }[name];
    window.scrollTo(0, 0);
  }

  function renderMusic() {
    const inside = !!session;
    $('auth').classList.toggle('hidden', inside);
    $('account').classList.toggle('hidden', !inside);
    $('who').textContent = session?.email || '';
    const all = [...tracks.values()];
    $('stSongs').textContent = all.length;
    $('stPlays').textContent = all.reduce((s, t) => s + (t.plays || 0), 0);
    $('stFavs').textContent = all.filter((t) => (t.likes || 0) > 0).length;
    const list = $('top');
    list.replaceChildren();
    for (const t of ranked().slice(0, 10)) {
      const li = document.createElement('li');
      li.textContent = t.title;
      const small = document.createElement('small');
      small.textContent = t.artist || '';
      li.appendChild(small);
      li.onclick = () => { showTab('home'); play({ title: t.title, artist: t.artist }); };
      list.appendChild(li);
    }
    if (!list.children.length) {
      const li = document.createElement('li');
      li.textContent = inside ? 'Aún no hay canciones. Pon música y di «Me gusta».' : 'Entra para ver tus canciones.';
      list.appendChild(li);
    }
    $('artists').textContent = topArtists(5).join(' · ') || '—';
  }

  function authMsg(text, error) {
    $('authMsg').textContent = text;
    $('authMsg').className = `small${error ? ' error' : ''}`;
  }

  async function doAuth(kind) {
    const email = $('email').value.trim();
    const password = $('password').value;
    if (!email.includes('@') || password.length < 6) {
      authMsg('Escribe tu correo y una contraseña de al menos 6 caracteres.', true);
      return;
    }
    authMsg('Un momento…');
    try {
      const json = kind === 'signup'
        ? await auth('signup', { email, password })
        : await auth('token?grant_type=password', { email, password });
      if (!json.access_token) { authMsg('Te enviamos un correo: confírmalo y luego toca «Entrar».'); return; }
      keep(json);
      authMsg('');
      $('password').value = '';
      await fetchTracks();
    } catch (e) {
      authMsg(e.message, true);
    }
  }

  // ================================================================ Inicio
  const actions = {
    next: () => next(true), previous, toggle, like, dislike,
    volumeUp: () => setVol(15), volumeDown: () => setVol(-15),
  };
  for (const b of document.querySelectorAll('[data-cmd]')) b.onclick = () => actions[b.dataset.cmd]();
  for (const b of document.querySelectorAll('.tabbar button')) b.onclick = () => showTab(b.dataset.tab);
  $('mic').onclick = () => (listening ? rec.stop() : startListening(true));
  $('fav').onclick = favorites;
  $('new').onclick = () => discover();
  $('search').onsubmit = (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (q) { $('q').blur(); play({ query: q }); }
  };
  $('login').onsubmit = (e) => { e.preventDefault(); doAuth('signin'); };
  $('signup').onclick = () => doAuth('signup');
  $('logout').onclick = signOut;
  const sel = $('target');
  for (const [id, a] of Object.entries(APPS)) {
    const o = document.createElement('option');
    o.value = id;
    o.textContent = id === 'here' ? 'Aquí mismo (SmartBuds)' : a.name;
    sel.appendChild(o);
  }
  sel.value = target;
  sel.onchange = () => { target = sel.value; saveJSON('smartbuds.target2', target); status(`Ahora la música se abre en ${APPS[target].name}.`); };
  $('continuous').checked = continuous;
  $('continuous').onchange = (e) => {
    continuous = e.target.checked;
    saveJSON('smartbuds.continuous', continuous);
    if (continuous) startListening(); else if (listening) rec.stop();
  };
  $('speakBack').checked = speakBack;
  $('speakBack').onchange = (e) => { speakBack = e.target.checked; saveJSON('smartbuds.speakBack', speakBack); };

  if (IOS) {
    $('iosNote').textContent = 'En iPhone: la música se detiene si bloqueas la pantalla o sales de la página, '
      + 'y el volumen se cambia con los botones del teléfono. Apple no deja a las páginas hacer más.';
    if (!STANDALONE) $('install').classList.remove('hidden');
  }
  $('playerWrap').classList.add('empty');
  $('nowSource').textContent = IOS ? 'SmartBuds no puede ver lo que suena en otras apps del iPhone'
                                   : 'SmartBuds';
  $('nowTitle').textContent = 'Pide una canción';
  if (!SB || !KEY) authMsg('Falta configurar Supabase en config.js.', true);
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
  setupVoice();
  renderMic();
  renderMusic();
  fetchTracks();
})();
