// Configuración pública de la página web.
// La clave «anon» de Supabase es pública por diseño: la protegen las reglas
// de seguridad (RLS) de supabase/schema.sql y supabase/cuentas.sql.
window.SMARTBUDS_CONFIG = {
  SUPABASE_URL: 'https://pgxbxtoaqhensfwiafdn.supabase.co',
  // Spotify dentro de SmartBuds (solo cuentas Premium). Es el «Client ID» de la
  // app creada en developer.spotify.com; es público (no es una contraseña).
  // Vacío = la opción no aparece.
  SPOTIFY_CLIENT_ID: '',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBneGJ4dG9hcWhlbnNmd2lhZmRuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwODEwOTMsImV4cCI6MjEwOTY1NzA5M30.XmnZuXEG58HYmzsD_vofbSKDsaBGRjNA95YiZNoRQ8g',
};
