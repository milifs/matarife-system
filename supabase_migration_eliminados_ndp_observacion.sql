-- Observación en remitos eliminados + tabla de auditoría para notas de pedido eliminadas

-- 1. Agregar columna observación a remitos_eliminados (paridad con pagos_eliminados)
ALTER TABLE remitos_eliminados ADD COLUMN IF NOT EXISTS observacion TEXT;

-- 2. Tabla de auditoría para notas de pedido eliminadas
CREATE TABLE IF NOT EXISTS notas_pedido_eliminadas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nota_pedido_id UUID NOT NULL,
  numero INT NOT NULL,
  fecha DATE NOT NULL,
  cliente_id UUID,
  cliente_nombre TEXT,
  estado TEXT,
  total_kg NUMERIC NOT NULL DEFAULT 0,
  total_pesos NUMERIC NOT NULL DEFAULT 0,
  observacion TEXT,
  eliminado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  eliminado_por TEXT
);

ALTER TABLE notas_pedido_eliminadas DISABLE ROW LEVEL SECURITY;
