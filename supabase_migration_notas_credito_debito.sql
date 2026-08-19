-- v18.21 — Notas de crédito y débito por cliente
-- NC (tipo='credito') resta al saldo del cliente (a su favor, como un pago).
-- ND (tipo='debito')  suma al saldo del cliente (cargo extra, como un remito).
-- Participan en el cálculo de saldo, el FIFO de vencidos, Historial y Reporte.

-- 1) Tabla principal
CREATE TABLE IF NOT EXISTS notas_credito_debito (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id UUID NOT NULL REFERENCES clientes(id),
  tipo TEXT NOT NULL CHECK (tipo IN ('credito', 'debito')),
  fecha DATE NOT NULL DEFAULT CURRENT_DATE,
  numero INT NOT NULL DEFAULT 0,
  monto NUMERIC NOT NULL DEFAULT 0,
  motivo TEXT DEFAULT '',
  registrado_por TEXT,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notas_cd_cliente
  ON notas_credito_debito (cliente_id);

ALTER TABLE notas_credito_debito DISABLE ROW LEVEL SECURITY;

-- 2) Auditoría de eliminadas (mismo patrón que pagos_eliminados / remitos_eliminados)
CREATE TABLE IF NOT EXISTS notas_cd_eliminadas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nota_id UUID,
  cliente_id UUID,
  tipo TEXT,
  fecha DATE,
  numero INT,
  monto NUMERIC,
  motivo TEXT,
  eliminado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  eliminado_por TEXT
);

ALTER TABLE notas_cd_eliminadas DISABLE ROW LEVEL SECURITY;
