-- v19.6 — Kg por media en los movimientos de depósito
--
-- Saber que hay 8 medias en la cámara no dice cuánto hay: dos medias pueden
-- diferenciarse en 40 kg. Para saber qué se guardó de verdad hacen falta los
-- kilos, no solo el conteo.
--
-- Mismo patrón que `nota_pedido_items.kgs_por_media`: un array con un valor
-- por media, no un total. Así se puede ver que la media que salió pesaba 118
-- y la que entró 95.
--
-- El total NO se guarda: se suma en Dart (`DepositoMovimiento.totalKg`). Es
-- la misma regla que el resto del módulo, donde nada que se pueda derivar se
-- persiste.
--
-- OJO: los kg son INFORMATIVOS. La ecuación del depósito sigue cerrando por
-- MEDIAS; los kilos se muestran pero no disparan la alerta de faltantes.
--
-- Son opcionales a propósito. Si el campo frenara el registro cuando la
-- cajera no tiene la balanza a mano, no registraría la salida — que es
-- exactamente el agujero que este módulo vino a tapar. Por eso el array
-- puede venir vacío o incompleto.

ALTER TABLE deposito_movimientos
  ADD COLUMN IF NOT EXISTS kgs_por_media JSONB NOT NULL DEFAULT '[]'::jsonb;

-- La auditoría también se los lleva: un movimiento borrado tiene que poder
-- reconstruirse entero, kilos incluidos.
ALTER TABLE deposito_movimientos_eliminados
  ADD COLUMN IF NOT EXISTS kgs_por_media JSONB NOT NULL DEFAULT '[]'::jsonb;
