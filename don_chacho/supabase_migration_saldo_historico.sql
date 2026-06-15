-- Migración: guardar saldos históricos en pagos
-- Permite regenerar el PDF de recibo con los saldos correctos al momento del pago

ALTER TABLE pagos
  ADD COLUMN IF NOT EXISTS saldo_anterior NUMERIC,
  ADD COLUMN IF NOT EXISTS saldo_nuevo NUMERIC;

-- Los pagos existentes quedarán con NULL en estos campos.
-- Al regenerar su recibo, el sistema usará una estimación basada en el saldo actual
-- (comportamiento anterior), pero los nuevos pagos ya guardarán los valores exactos.
