-- Tabla de auditoría para remitos eliminados
CREATE TABLE IF NOT EXISTS remitos_eliminados (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  remito_id UUID NOT NULL,
  cliente_id UUID NOT NULL,
  fecha DATE NOT NULL,
  numero INT NOT NULL,
  total_kg NUMERIC NOT NULL DEFAULT 0,
  total_pesos NUMERIC NOT NULL DEFAULT 0,
  eliminado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  eliminado_por TEXT
);

ALTER TABLE remitos_eliminados DISABLE ROW LEVEL SECURITY;
