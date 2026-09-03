// ============================================================
// SUPABASE EDGE FUNCTION - parse-reparto
// ============================================================
// Interpreta una frase dictada/escrita por Joaco para armar la
// lista de reparto (Jueves/Viernes) y devuelve items estructurados.
// Ej: "Para el jueves cargame 3 medias de cerdo y 2 de carne para Perico"
//   -> { dia: "jueves", items: [{ accion:"cargar", cliente:"Perico",
//         carne:2, cerdo:3, sucursal:"", confianza:"alta" }] }
//
// Es un parseo de UN solo paso (texto -> JSON), sin loop de herramientas.
// Se usa como proxy a la API de Claude para no exponer la API key en el
// cliente y evitar CORS.
// ============================================================
//
// INSTRUCCIONES DE DEPLOY (por dashboard de Supabase):
// 1. Edge Functions -> Create a new function -> nombre: parse-reparto
// 2. Pegar el contenido de este archivo
// 3. El secret ANTHROPIC_API_KEY ya está configurado en el proyecto
// 4. Deploy con "Verify JWT" ON (la publishable key lo satisface)
// ============================================================

import "https://deno.land/x/xhr@0.3.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { texto, dia_actual, clientes, model } = await req.json();

    if (!texto || typeof texto !== "string" || !texto.trim()) {
      return jsonResponse({ error: "Falta el texto a interpretar" }, 400);
    }

    // Modelo overridable desde el body; por defecto Sonnet 4.5, que
    // matchea bien nombres con acentos/errores de dictado.
    const modelo =
      typeof model === "string" && model.trim()
        ? model.trim()
        : "claude-sonnet-4-5-20250929";

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return jsonResponse({ error: "ANTHROPIC_API_KEY no configurada" }, 500);
    }

    // Lista de nombres reales de clientes para que Claude matchee bien
    // pese a errores de dictado / acentos.
    const nombres: string[] = Array.isArray(clientes)
      ? clientes.filter((c) => typeof c === "string" && c.trim()).map((c) => c.trim())
      : [];

    const diaActual =
      dia_actual === "jueves" || dia_actual === "viernes" ? dia_actual : null;

    const prompt = `Sos un asistente que interpreta pedidos de reparto de carne de una carnicería mayorista argentina y los convierte en datos estructurados.

CONTEXTO:
- El reparto se arma por día: solo "jueves" o "viernes".
- Hay dos tipos de mercadería: "carne" (novillo) y "cerdo". La unidad es "medias" (medias reses).
- El usuario dicta o escribe frases informales, por ejemplo:
  - "Para el jueves cargame 3 medias de cerdo y 2 medias de carne para Perico"
  - "2 de carne para La Florida y 3 de cerdo para el Gordo"
  - "sacá a Perico del viernes"
  - "para Distribuidora Sur, sucursal Centro, 4 de carne"

DÍA:
- Si menciona un día (jueves/viernes), poné ese día en "dia".
- Si NO menciona ningún día, poné "dia": ${diaActual ? `"${diaActual}"` : "null"} (es el día que el usuario tiene abierto en pantalla).

ACCIONES (campo "accion"):
- "cargar": agregar o actualizar cantidades de un cliente.
- "borrar": quitar a un cliente del reparto (cuando dice "sacá", "borrá", "quitá", "eliminá").

CANTIDADES:
- "carne" y "cerdo" son enteros. Si no menciona uno de los dos, poné 0.
- En acciones "borrar", poné carne=0 y cerdo=0 (se ignoran).

CLIENTE (muy importante):
- Tenés esta lista de clientes REALES. Para cada item elegí el nombre EXACTO de la lista que mejor coincida, tolerando errores de dictado, mayúsculas y acentos.
- Si ninguno coincide con seguridad razonable, poné "cliente": null y "confianza": "dudosa".
- Si coincide claramente, "confianza": "alta".
- LISTA DE CLIENTES:
${nombres.length ? nombres.map((n) => `  - ${n}`).join("\n") : "  (lista vacía)"}

SUCURSAL:
- Si menciona una sucursal específica del cliente, ponela en "sucursal" (texto corto). Si no, "".

FORMATO DE RESPUESTA:
Respondé SOLO con un JSON válido, sin texto adicional, sin backticks, con esta estructura EXACTA:
{
  "dia": "jueves" | "viernes" | null,
  "items": [
    {
      "accion": "cargar" | "borrar",
      "cliente": "nombre exacto de la lista" | null,
      "carne": número entero,
      "cerdo": número entero,
      "sucursal": "texto" | "",
      "confianza": "alta" | "dudosa"
    }
  ]
}

Si no entendés ningún pedido concreto, devolvé "items": [].

FRASE A INTERPRETAR:
"${texto.trim()}"`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: modelo,
        max_tokens: 1500,
        messages: [{ role: "user", content: [{ type: "text", text: prompt }] }],
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      return jsonResponse(
        { error: `API error: ${response.status}`, details: data },
        response.status,
      );
    }

    const text = data.content?.[0]?.text || "";

    try {
      const clean = text.replace(/```json/g, "").replace(/```/g, "").trim();
      const parsed = JSON.parse(clean);
      return jsonResponse(parsed);
    } catch {
      return jsonResponse({ raw_text: text, parse_error: true }, 200);
    }
  } catch (error) {
    return jsonResponse({ error: (error as Error).message }, 500);
  }
});
