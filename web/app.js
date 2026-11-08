// SmartBuds AI — versión web (para iPhone o cualquier navegador).
// Lee tus gustos de Supabase (la misma cuenta de la app de Android) y abre las
// canciones en YouTube Music. Sin librerías: solo fetch a la API REST.
(() => {
  'use strict';
  const { SUPABASE_URL: URL_BASE, SUPABASE_ANON_KEY: KEY } = window.SMARTBUDS_CONFIG || {};
  const $ = (id) => document.getElementById(id);
  const STORE = 'smartbuds.session';
  // Mismos pesos que la app: completa +2, repetida +3, me gusta +5, saltada −2, no me gusta −5.
  const W = { completes: 2, repeats: 3, likes: 5, skips: -2, dislikes: -5 };

  let tracks = [];

  // ------------------------------------------------------------ Sesión
  const load = () => {
    try { return JSON.parse(localStorage.getItem(STORE)); } catch { return null; }
  };
  const save = (s) => {
    try { s ? localStorage.setItem(STORE, JSON.stringify(s)) : localStorage.removeItem(STORE); }
    catch { /* modo privado: la sesión dura solo esta visita */ }
  };
  let session = load();

  async function auth(path, body) {
    const res = await fetch(`${URL_BASE}/auth/v1/${path}`, {
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
      email: json.user?.email,
      uid: json.user?.id,
    };
    save(session);
  }

  async function token() {
    if (!session) return null;
    if (Date.now() < session.exp - 120000) return session.access;
    try {
      keep({ ...(await auth('token?grant_type=refresh_token', { refresh_token: session.refresh })),
             user: { email: session.email, id: session.uid } });
      return session.access;
    } catch {
      signOut();
      return null;
    }
  }

  function signOut() {
    session = null;
    save(null);
    tracks = [];
    render();
  }

  // ------------------------------------------------------------ Datos
  async function fetchTracks() {
    const t = await token();
    if (!t) return;
    const id = encodeURIComponent(`u:${session.uid}`);
    const res = await fetch(`${URL_BASE}/rest/v1/track_scores?select=*&device_id=eq.${id}&limit=2000`, {
      headers: { apikey: KEY, Authorization: `Bearer ${t}` },
    });
    if (!res.ok) { status('No pude traer tus canciones.'); return; }
    tracks = (await res.json()).map((r) => ({ ...r, score: score(r) }))
      .sort((a, b) => b.score - a.score);
    render();
  }

  const score = (r) => Object.entries(W).reduce((s, [k, w]) => s + (r[k] || 0) * w, 0);

  function topArtists(n) {
    const by = {};
    for (const t of tracks) if (t.artist && t.score > 0) by[t.artist] = (by[t.artist] || 0) + t.score;
    return Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, n).map(([a]) => a);
  }

  // ------------------------------------------------------------ Acciones
  // Enlace de búsqueda de YouTube Music: en iPhone abre la app si está instalada.
  function play(query) {
    status(`Abriendo «${query}» en YouTube Music…`);
    window.location.href = `https://music.youtube.com/search?q=${encodeURIComponent(query)}`;
  }

  function playFavorite() {
    const good = tracks.filter((t) => t.score > 0).slice(0, 15);
    if (!good.length) {
      status(session ? 'Aún no conozco tus gustos: escucha música con la app y di «Me gusta».'
                     : 'Entra con tu cuenta para ver tus gustos.');
      return;
    }
    // Al azar, pero las mejores tienen más probabilidad.
    const total = good.reduce((s, t) => s + t.score, 0);
    let r = Math.random() * total;
    const pick = good.find((t) => (r -= t.score) <= 0) || good[0];
    play([pick.title, pick.artist].filter(Boolean).join(' '));
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

  async function discover() {
    const mine = topArtists(3);
    if (!mine.length) { play('éxitos del momento'); return; }
    const seed = mine[Math.floor(Math.random() * mine.length)];
    status(`Buscando artistas parecidos a ${seed}…`);
    try {
      const found = await deezer(`/search/artist?q=${encodeURIComponent(seed)}&limit=1`);
      const id = found.data?.[0]?.id;
      const known = new Set(tracks.map((t) => (t.artist || '').toLowerCase()));
      const related = (await deezer(`/artist/${id}/related?limit=10`)).data || [];
      const fresh = related.filter((a) => !known.has(a.name.toLowerCase()));
      const artist = fresh[Math.floor(Math.random() * fresh.length)] || related[0];
      const top = (await deezer(`/artist/${artist.id}/top?limit=5`)).data || [];
      const song = top[Math.floor(Math.random() * top.length)];
      play(song ? `${song.title} ${artist.name}` : artist.name);
    } catch {
      play(`${seed} mix`);
    }
  }

  // ------------------------------------------------------------ Voz (con la página abierta)
  function setupMic() {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SR) { $('mic').classList.add('hidden'); $('micHint').textContent = 'Escribe la canción y toca ▶.'; return; }
    const rec = new SR();
    rec.lang = 'es-CO';
    rec.interimResults = false;
    rec.maxAlternatives = 1;
    rec.onstart = () => { $('mic').classList.add('listening'); status('Te escucho…'); };
    rec.onend = () => $('mic').classList.remove('listening');
    rec.onerror = () => status('No te entendí. Inténtalo otra vez.');
    rec.onresult = (e) => {
      const said = e.results[0][0].transcript.trim();
      $('q').value = said;
      const n = said.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
      if (/^pon algo que me guste|^mis favoritas/.test(n)) return playFavorite();
      if (/^(pon )?algo nuevo|^sorprendeme/.test(n)) return discover();
      play(said.replace(/^(busca(r|me)?|pon)\s+/i, ''));
    };
    $('mic').onclick = () => { try { rec.start(); } catch { /* ya escuchando */ } };
  }

  // ------------------------------------------------------------ Pantalla
  function status(msg) { $('status').textContent = msg || ''; }

  function render() {
    const inside = !!session;
    $('auth').classList.toggle('hidden', inside);
    $('mine').classList.toggle('hidden', !inside);
    $('logout').classList.toggle('hidden', !inside);
    $('who').textContent = inside ? session.email : 'Tu música, a un toque';
    const list = $('top');
    list.replaceChildren();
    for (const t of tracks.filter((x) => x.score > 0).slice(0, 10)) {
      const li = document.createElement('li');
      li.textContent = t.title;
      const small = document.createElement('small');
      small.textContent = t.artist || '';
      li.appendChild(small);
      li.onclick = () => play([t.title, t.artist].filter(Boolean).join(' '));
      list.appendChild(li);
    }
    if (inside && !list.children.length) {
      const li = document.createElement('li');
      li.textContent = 'Aún no hay canciones. Escucha música con la app y di «Me gusta».';
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
      if (!json.access_token) {
        authMsg('Te enviamos un correo: confírmalo y luego toca «Entrar».');
        return;
      }
      keep(json);
      authMsg('');
      $('password').value = '';
      render();
      await fetchTracks();
    } catch (e) {
      authMsg(e.message, true);
    }
  }

  // ------------------------------------------------------------ Inicio
  $('login').onsubmit = (e) => { e.preventDefault(); doAuth('signin'); };
  $('signup').onclick = () => doAuth('signup');
  $('logout').onclick = signOut;
  $('fav').onclick = playFavorite;
  $('new').onclick = discover;
  $('search').onsubmit = (e) => {
    e.preventDefault();
    const q = $('q').value.trim();
    if (q) play(q);
  };

  // Aviso de instalación en Safari del iPhone (si aún no se abrió desde inicio).
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
  const standalone = window.navigator.standalone || matchMedia('(display-mode: standalone)').matches;
  if (ios && !standalone) $('install').classList.remove('hidden');

  if (!URL_BASE || !KEY) {
    authMsg('Falta configurar Supabase en config.js.', true);
  }
  if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
  setupMic();
  render();
  fetchTracks();
})();
