-- ============================================================
-- MIGRACIÓN v18: Notas de Pedido
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- Tabla principal
CREATE TABLE IF NOT EXISTS notas_pedido (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  numero INTEGER NOT NULL DEFAULT 0,
  fecha DATE NOT NULL,
  cliente_id UUID REFERENCES clientes(id) ON DELETE SET NULL,
  cliente_nombre_libre TEXT,
  estado TEXT NOT NULL DEFAULT 'pendiente'
    CHECK (estado IN ('pendiente', 'confirmado', 'rechazado')),
  motivo_rechazo TEXT,
  creado_por UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  confirmado_por UUID REFERENCES usuarios(id) ON DELETE SET NULL,
  confirmado_en TIMESTAMPTZ,
  remito_id UUID REFERENCES remitos(id) ON DELETE SET NULL,
  total_kg NUMERIC NOT NULL DEFAULT 0,
  total_pesos NUMERIC NOT NULL DEFAULT 0,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Items de la nota de pedido
CREATE TABLE IF NOT EXISTS nota_pedido_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nota_pedido_id UUID NOT NULL REFERENCES notas_pedido(id) ON DELETE CASCADE,
  descripcion TEXT NOT NULL DEFAULT '',
  cantidad_medias INTEGER NOT NULL DEFAULT 1,
  kgs_por_media JSONB NOT NULL DEFAULT '[]'::jsonb,
  precio_por_media NUMERIC NOT NULL DEFAULT 0,
  total_kg NUMERIC NOT NULL DEFAULT 0,
  total_pesos NUMERIC NOT NULL DEFAULT 0
);

-- RLS deshabilitado (consistente con el resto de la app)
ALTER TABLE notas_pedido DISABLE ROW LEVEL SECURITY;
ALTER TABLE nota_pedido_items DISABLE ROW LEVEL SECURITY;
