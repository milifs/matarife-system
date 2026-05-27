-- ============================================================
-- GRANJA DON CHACHO - Módulo Matarife Terceros
-- Script de creación de tablas para Supabase (PostgreSQL)
-- ============================================================
-- Ejecutar en: Supabase Dashboard > SQL Editor
-- ============================================================

-- ── Vendedores (comisionistas) ──
CREATE TABLE IF NOT EXISTS vendedores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre TEXT NOT NULL,
  apellido TEXT NOT NULL,
  telefono TEXT DEFAULT '',
  creado_en TIMESTAMPTZ DEFAULT NOW(),
  activo BOOLEAN DEFAULT TRUE
);

-- ── Clientes (pertenecen a un vendedor) ──
CREATE TABLE IF NOT EXISTS clientes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre_razon_social TEXT NOT NULL,
  telefono TEXT DEFAULT '',
  vendedor_id UUID NOT NULL REFERENCES vendedores(id),
  plazo_pago_dias INTEGER DEFAULT 7,
  creado_en TIMESTAMPTZ DEFAULT NOW(),
  activo BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_clientes_vendedor ON clientes(vendedor_id);

-- ── Remitos (cabecera) ──
CREATE TABLE IF NOT EXISTS remitos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id UUID NOT NULL REFERENCES clientes(id),
  fecha DATE NOT NULL DEFAULT CURRENT_DATE,
  foto_url TEXT,
  total_kg NUMERIC(10,2) DEFAULT 0,
  total_pesos NUMERIC(14,2) DEFAULT 0,
  creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_remitos_cliente ON remitos(cliente_id);
CREATE INDEX idx_remitos_fecha ON remitos(fecha);

-- ── Remito Items (líneas de detalle) ──
CREATE TABLE IF NOT EXISTS remito_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  remito_id UUID NOT NULL REFERENCES remitos(id) ON DELETE CASCADE,
  tipo_carne TEXT NOT NULL,
  cantidad_medias INTEGER NOT NULL,
  kg_total NUMERIC(10,2) NOT NULL,
  precio_por_kg NUMERIC(10,2) NOT NULL
);

CREATE INDEX idx_remito_items_remito ON remito_items(remito_id);

-- ── Pagos (cabecera) ──
CREATE TABLE IF NOT EXISTS pagos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id UUID NOT NULL REFERENCES clientes(id),
  fecha DATE NOT NULL DEFAULT CURRENT_DATE,
  monto_total NUMERIC(14,2) NOT NULL,
  neto_recibido NUMERIC(14,2) NOT NULL,
  creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_pagos_cliente ON pagos(cliente_id);
CREATE INDEX idx_pagos_fecha ON pagos(fecha);

-- ── Pago Medios (forma de pago individual) ──
CREATE TABLE IF NOT EXISTS pago_medios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pago_id UUID NOT NULL REFERENCES pagos(id) ON DELETE CASCADE,
  medio TEXT NOT NULL CHECK (medio IN ('efectivo', 'transferencia', 'cheque')),
  monto NUMERIC(14,2) NOT NULL,
  descuento NUMERIC(14,2) DEFAULT 0,
  neto_recibido NUMERIC(14,2) NOT NULL
);

CREATE INDEX idx_pago_medios_pago ON pago_medios(pago_id);

-- ── Costos Semanales ──
CREATE TABLE IF NOT EXISTS costos_semana (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  semana_inicio DATE NOT NULL UNIQUE,
  costo_por_kg NUMERIC(10,2) NOT NULL,
  creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- ── Storage bucket para fotos de remitos ──
-- Ejecutar por separado o desde el dashboard:
-- INSERT INTO storage.buckets (id, name, public) 
-- VALUES ('fotos-remitos', 'fotos-remitos', true);

-- ── Row Level Security (básico - acceso total para auth) ──
ALTER TABLE vendedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE remitos ENABLE ROW LEVEL SECURITY;
ALTER TABLE remito_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos ENABLE ROW LEVEL SECURITY;
ALTER TABLE pago_medios ENABLE ROW LEVEL SECURITY;
ALTER TABLE costos_semana ENABLE ROW LEVEL SECURITY;

-- Política: acceso total para usuarios autenticados
-- (como solo vos usás la app, esto es suficiente)
CREATE POLICY "Acceso total autenticado" ON vendedores FOR ALL USING (true);
CREATE POLICY "Acceso total autenticado" ON clientes FOR ALL USING (true);
CREATE POLICY "Acceso total autenticado" ON remitos FOR ALL USING (true);
CREATE POLICY "Acceso total autenticado" ON remito_items FOR ALL USING (true);
CREATE POLICY "Acceso total autenticado" ON pagos FOR ALL USING (true);
CREATE POLICY "Acceso total autenticado" ON pago_medios FOR ALL USING (true);
CREATE POLICY "Acceso total autenticado" ON costos_semana FOR ALL USING (true);

-- ── Vista útil: saldo por cliente ──
CREATE OR REPLACE VIEW vista_saldos_clientes AS
SELECT 
  c.id AS cliente_id,
  c.nombre_razon_social,
  c.vendedor_id,
  c.plazo_pago_dias,
  v.nombre || ' ' || v.apellido AS vendedor_nombre,
  COALESCE(SUM(r.total_pesos), 0) AS total_remitos,
  COALESCE(
    (SELECT SUM(p.monto_total) FROM pagos p WHERE p.cliente_id = c.id), 
    0
  ) AS total_pagos,
  COALESCE(SUM(r.total_pesos), 0) - COALESCE(
    (SELECT SUM(p.monto_total) FROM pagos p WHERE p.cliente_id = c.id), 
    0
  ) AS saldo
FROM clientes c
LEFT JOIN vendedores v ON v.id = c.vendedor_id
LEFT JOIN remitos r ON r.cliente_id = c.id
WHERE c.activo = TRUE
GROUP BY c.id, c.nombre_razon_social, c.vendedor_id, c.plazo_pago_dias,
         v.nombre, v.apellido;
