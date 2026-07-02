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
// INSTRUCCIONES DE DEPLOY:
// 1. Copiá este archivo a supabase/functions/resolver-maps/index.ts
// 2. Deployá: supabase functions deploy resolver-maps --no-verify-jwt
// ============================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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

  // ?q= / query= / ll= / daddr= / destination= / center= / sll=
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

// Sigue los redirects de una URL corta y devuelve la URL final.
async function resolverUrl(url: string): Promise<string> {
  // Primero probamos leer el location header sin seguir automáticamente.
  try {
    const res = await fetch(url, {
      method: "GET",
      redirect: "manual",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
          "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      },
    });
    const loc = res.headers.get("location");
    if (loc) return loc;
    // Si no hubo redirect pero trajo HTML, devolvemos el body para escanear.
    const body = await res.text();
    return body;
  } catch (_) {
    // Fallback: seguir redirects automáticamente.
    try {
      const res = await fetch(url, {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0 Safari/537.36",
        },
      });
      return res.url + " " + (await res.text());
    } catch (_) {
      return "";
    }
  }
}

async function coordsDeLink(url: string): Promise<
  { lat: number; lng: number } | null
> {
  // Si ya trae coords, no hace falta resolver.
  const directo = parseCoords(url);
  if (directo) return directo;

  const final = await resolverUrl(url);
  const c = parseCoords(final);
  if (c) return c;

  // A veces el redirect final es otro link corto; probamos una vez más.
  const segundo = final.match(/https?:\/\/[^\s"'<>]+/);
  if (segundo) {
    const final2 = await resolverUrl(segundo[0]);
    return parseCoords(final2);
  }
  return null;
}

serve(async (req) => {
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
          const c = await coordsDeLink(url);
          return { url, lat: c?.lat ?? null, lng: c?.lng ?? null };
        } catch (_) {
          return { url, lat: null, lng: null };
        }
      }),
    );

    return new Response(
      JSON.stringify({ results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
