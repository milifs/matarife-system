-- ============================================================
-- BACKFILL de saldo_anterior / saldo_nuevo en pagos
-- ============================================================
-- Calcula, para cada pago, el saldo del cliente JUSTO DESPUÉS de ese pago
-- (saldo_nuevo) y justo antes (saldo_anterior), en orden cronológico
-- (fecha, luego numero). Así cada recibo reimpreso muestra el saldo real
-- de ese momento y no el saldo actual.
--
--   saldo_nuevo    = (total remitos confirmados del cliente) - (pagos hasta este inclusive)
--   saldo_anterior = saldo_nuevo + monto_total de este pago
--
-- Sobrescribe TODOS los pagos para que queden consistentes con los remitos
-- confirmados actuales. Correr una sola vez en el SQL Editor de Supabase.
-- ============================================================

WITH remito_totales AS (
  SELECT cliente_id, SUM(total_pesos) AS total_remitos
  FROM remitos
  WHERE estado = 'confirmado'
  GROUP BY cliente_id
),
pagos_acum AS (
  SELECT
    id,
    cliente_id,
    monto_total,
    SUM(monto_total) OVER (
      PARTITION BY cliente_id
      ORDER BY fecha, numero
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS pagos_hasta
  FROM pagos
)
UPDATE pagos p
SET
  saldo_nuevo    = COALESCE(rt.total_remitos, 0) - a.pagos_hasta,
  saldo_anterior = COALESCE(rt.total_remitos, 0) - a.pagos_hasta + a.monto_total
FROM pagos_acum a
LEFT JOIN remito_totales rt ON rt.cliente_id = a.cliente_id
WHERE p.id = a.id;
