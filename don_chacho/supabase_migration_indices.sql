-- Ejecutar este script una vez en Supabase Dashboard > SQL Editor para acelerar la carga inicial.

-- Índices para mejorar la performance de carga inicial
-- Ejecutar UNA SOLA VEZ en el SQL Editor de Supabase.

CREATE INDEX IF NOT EXISTS idx_remito_items_remito_id
  ON remito_items(remito_id);

CREATE INDEX IF NOT EXISTS idx_nota_pedido_items_nota_id
  ON nota_pedido_items(nota_pedido_id);

CREATE INDEX IF NOT EXISTS idx_pago_medios_pago_id
  ON pago_medios(pago_id);

CREATE INDEX IF NOT EXISTS idx_remitos_estado
  ON remitos(estado);

CREATE INDEX IF NOT EXISTS idx_remitos_fecha_desc
  ON remitos(fecha DESC);

CREATE INDEX IF NOT EXISTS idx_pagos_fecha_desc
  ON pagos(fecha DESC);
