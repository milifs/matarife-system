// ============================================================
// SUPABASE EDGE FUNCTION - Resolver links de Google Maps
// ============================================================
// Los links cortos (maps.app.goo.gl/XXXX) no traen coordenadas y
// el navegador no puede seguir el redirect por CORS. Esta función
// hace el fetch del lado del servidor, sigue los redirects y extrae
// las coordenadas del link final.
// Recibe un lote de URLs y devuelve las coordenadas de cada una.
// ============================================================
//
// DEPLOY (dashboard): Edge Functions -> Deploy a new function ->
//   nombre: resolver-maps -> pegar este archivo.
// DEPLOY (CLI): supabase functions deploy resolver-maps --no-verify-jwt
// ============================================================

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "jsr:@supabase/server@^1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/120.0 Safari/537.36";

// Extrae lat,lng del texto de una URL de Google Maps (formato completo).
function parseCoords(texto: string): { lat: number; lng: number } | null {
  if (!texto) return null;
  let s = texto;
  try {
    s = decodeURIComponent(texto);
  } catch (_) {
    s = texto;
  }

  const build = (a: string, b: string) => {
    const lat = parseFloat(a);
    const lng = parseFloat(b);
    if (isNaN(lat) || isNaN(lng)) return null;
    if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
    return { lat, lng };
  };

  // !3d<lat>!4d<lng>
  let m = s.match(/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/);
  if (m) return build(m[1], m[2]);

  // @<lat>,<lng>
  m = s.match(/@(-?\d+\.\d+),(-?\d+\.\d+)/);
  if (m) return build(m[1], m[2]);

  // ?q= / query= / ll= / sll= / daddr= / destination= / center=
  m = s.match(
    /[?&](?:q|query|ll|sll|daddr|destination|center)=(-?\d+\.\d+),(-?\d+\.\d+)/,
  );
  if (m) return build(m[1], m[2]);

  // Formato DMS: 24°59'04.1"S 65°22'17.8"W
  const dmsRe =
    /(\d{1,3})\s*[°º]\s*(\d{1,2})\s*['′]\s*([\d.]+)\s*["″]\s*([NSEWnsew])/g;
  const dmsMatches = [...s.matchAll(dmsRe)];
  if (dmsMatches.length >= 2) {
    let lat: number | null = null;
    let lng: number | null = null;
    for (const dm of dmsMatches) {
      const deg = parseFloat(dm[1]);
      const min = parseFloat(dm[2]);
      const sec = parseFloat(dm[3]);
      const hemi = dm[4].toUpperCase();
      let val = deg + min / 60 + sec / 3600;
      if (hemi === "S" || hemi === "W") val = -val;
      if (hemi === "N" || hemi === "S") {
        if (lat === null) lat = val;
      } else {
        if (lng === null) lng = val;
      }
    }
    if (lat !== null && lng !== null) {
      return build(String(lat), String(lng));
    }
  }

  return null;
}

// Sigue los redirects de una URL corta y devuelve la URL final (o el body).
async function resolverUrl(url: string): Promise<string> {
  try {
    const res = await fetch(url, {
      method: "GET",
      redirect: "manual",
      headers: { "User-Agent": UA },
    });
    const loc = res.headers.get("location");
    if (loc) return loc;
    return await res.text();
  } catch (_) {
    try {
      const res = await fetch(url, { headers: { "User-Agent": UA } });
      return res.url + " " + (await res.text());
    } catch (_) {
      return "";
    }
  }
}

// Extrae un nombre de lugar / dirección de texto de la URL, para links
// que se compartieron como "lugar" y no traen coordenadas.
function parseDireccion(texto: string): string | null {
  if (!texto) return null;
  const m = texto.match(/[?&](?:q|query|destination|daddr)=([^&]+)/);
  if (!m) return null;
  let val = m[1];
  try {
    val = decodeURIComponent(val.replace(/\+/g, " "));
  } catch (_) {
    val = val.replace(/\+/g, " ");
  }
  val = val.trim();
  // Descartar si es un par de coordenadas (eso ya lo maneja parseCoords).
  if (/^-?\d+\.\d+,-?\d+\.\d+$/.test(val)) return null;
  if (val.length < 2) return null;
  return val;
}

interface Resuelto {
  lat: number | null;
  lng: number | null;
  direccion: string | null;
}

async function resolverLink(url: string): Promise<Resuelto> {
  const vacio: Resuelto = { lat: null, lng: null, direccion: null };

  const directo = parseCoords(url);
  if (directo) return { lat: directo.lat, lng: directo.lng, direccion: null };

  let final = await resolverUrl(url);
  let c = parseCoords(final);
  if (c) return { lat: c.lat, lng: c.lng, direccion: null };

  // A veces el redirect final es otro link corto; probamos una vez más.
  const segundo = final.match(/https?:\/\/[^\s"'<>]+/);
  if (segundo) {
    const final2 = await resolverUrl(segundo[0]);
    c = parseCoords(final2);
    if (c) return { lat: c.lat, lng: c.lng, direccion: null };
    final = final2 || final;
  }

  // Sin coordenadas: intentamos rescatar un nombre de lugar / dirección.
  const dir = parseDireccion(final);
  if (dir) return { lat: null, lng: null, direccion: dir };
  return vacio;
}

console.info("resolver-maps started");

export default {
  fetch: withSupabase(
    { auth: ["publishable", "secret"] },
    async (req: Request) => {
      if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
      }

      try {
        const { urls } = await req.json();
        if (!Array.isArray(urls)) {
          return new Response(
            JSON.stringify({ error: "Falta el array 'urls'" }),
            {
              status: 400,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        const results = await Promise.all(
          urls.map(async (url: string) => {
            try {
              const r = await resolverLink(url);
              return { url, lat: r.lat, lng: r.lng, direccion: r.direccion };
            } catch (_) {
              return { url, lat: null, lng: null, direccion: null };
            }
          }),
        );

        return new Response(JSON.stringify({ results }), {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: String(e) }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
    },
  ),
};
