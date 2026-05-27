// ============================================================
// SUPABASE EDGE FUNCTION - OCR Proxy para Claude API
// ============================================================
// Esta función recibe la imagen en base64 desde la app Flutter
// y la envía a la API de Claude para extraer los datos del remito.
// Se usa como proxy para evitar el bloqueo de CORS del navegador.
// ============================================================
// 
// INSTRUCCIONES DE DEPLOY:
// 1. Instalá Supabase CLI: npm install -g supabase
// 2. Logueate: supabase login
// 3. Linkeá tu proyecto: supabase link --project-ref TU_PROJECT_REF
// 4. Creá la función: supabase functions new ocr-remito
// 5. Reemplazá el contenido de supabase/functions/ocr-remito/index.ts con este archivo
// 6. Configurá el secret: supabase secrets set ANTHROPIC_API_KEY=tu_api_key_aqui
// 7. Deployá: supabase functions deploy ocr-remito --no-verify-jwt
// ============================================================

import "https://deno.land/x/xhr@0.3.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Manejar preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { image_base64, media_type } = await req.json();

    if (!image_base64) {
      return new Response(
        JSON.stringify({ error: "Falta image_base64" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "ANTHROPIC_API_KEY no configurada" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1000,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: media_type || "image/jpeg",
                  data: image_base64,
                },
              },
              {
                type: "text",
                text: `Analizá esta foto de un remito/planilla de venta de medias reses.
Extraé los siguientes datos de UNA SOLA FILA (un solo cliente):

Respondé SOLO con un JSON válido, sin texto adicional, sin backticks, con esta estructura exacta:
{
  "cliente": "nombre del cliente",
  "fecha": "DD/MM/YYYY",
  "cant_medias": número,
  "kg_por_media": [lista de kg de cada media individual, ej: [78.5, 82.0, 75.3]],
  "total_kg": número total de kg,
  "precio_media": precio por media en pesos (número sin símbolo),
  "total_pesos": total en pesos (número sin símbolo)
}

Si algún dato no se puede leer, poné null en ese campo.
Los kg_por_media deben ser los kg individuales de cada media res que aparecen en las columnas del remito.
Si no hay kg individuales, estimá dividiendo total_kg / cant_medias.
Respondé SOLO el JSON, nada más.`,
              },
            ],
          },
        ],
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      return new Response(
        JSON.stringify({ error: `API error: ${response.status}`, details: data }),
        { status: response.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Extraer el texto de la respuesta de Claude
    const text = data.content?.[0]?.text || "";

    // Intentar parsear el JSON de la respuesta
    let parsed;
    try {
      const cleanJson = text.replace(/```json/g, "").replace(/```/g, "").trim();
      parsed = JSON.parse(cleanJson);
    } catch {
      parsed = { raw_text: text, parse_error: true };
    }

    return new Response(
      JSON.stringify(parsed),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
