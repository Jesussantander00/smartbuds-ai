// Búsqueda de canciones en YouTube para la página web.
// Corre en Vercel (servidor): la clave de YouTube vive en la variable de entorno
// YOUTUBE_API_KEY y nunca llega al navegador.
//
// GET /api/search?q=ojala+ryan+castro  →  [{ id, title, channel }]

const cache = new Map(); // búsquedas recientes (ahorra cuota de YouTube)
const MAX_CACHE = 300;

module.exports = async function handler(req, res) {
  const q = String(req.query.q || '').trim().slice(0, 120);
  if (!q) return res.status(400).json({ error: 'Falta q' });

  const key = process.env.YOUTUBE_API_KEY;
  if (!key) {
    return res.status(503).json({ error: 'Falta YOUTUBE_API_KEY en Vercel' });
  }

  const hit = cache.get(q.toLowerCase());
  if (hit) return send(res, hit);

  const url = new URL('https://www.googleapis.com/youtube/v3/search');
  url.search = new URLSearchParams({
    part: 'snippet',
    type: 'video',
    videoCategoryId: '10', // Música
    videoEmbeddable: 'true', // que se pueda reproducir dentro de la página
    maxResults: '8',
    q,
    key,
  }).toString();

  try {
    const r = await fetch(url);
    if (!r.ok) return res.status(502).json({ error: `YouTube respondió ${r.status}` });
    const data = await r.json();
    const items = (data.items || [])
      .filter((it) => it.id && it.id.videoId)
      .map((it) => ({
        id: it.id.videoId,
        title: unescape(it.snippet.title),
        channel: unescape(it.snippet.channelTitle || ''),
        thumb: it.snippet.thumbnails?.default?.url || '',
      }));
    if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value);
    cache.set(q.toLowerCase(), items);
    return send(res, items);
  } catch {
    return res.status(502).json({ error: 'No se pudo contactar a YouTube' });
  }
};

function send(res, items) {
  res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=604800');
  return res.status(200).json(items);
}

function unescape(s) {
  return String(s)
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}
