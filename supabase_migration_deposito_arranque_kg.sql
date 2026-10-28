-- v19.9 — Kg del arranque del depósito
--
-- Desde v19.6 cada movimiento guarda los kilos de sus medias, pero el
-- ARRANQUE no tenía dónde ponerlos: se contaban las medias de la cámara y los
-- kilos de esas medias se perdían. Sin ese dato no hay kilaje de stock
-- posible, porque la primera línea de la ecuación quedaría sin pesar y todo
-- lo demás colgaría de un número incompleto.
--
-- Son OPCIONALES, igual que el resto de los kilos del módulo: si la cajera
-- cuenta la cámara sin balanza, el arranque se guarda igual y el kilaje
-- aparece marcado como incompleto en vez de bloquear la carga.
--
-- Los kilos siguen siendo INFORMATIVOS: la ecuación del depósito cierra por
-- MEDIAS y la alerta de faltantes también. Esto solo agrega el "cuánto pesa"
-- a lo que ya se sabía que estaba.

ALTER TABLE deposito_config
  ADD COLUMN IF NOT EXISTS kg_novillo NUMERIC(12,2) NOT NULL DEFAULT 0;

ALTER TABLE deposito_config
  ADD COLUMN IF NOT EXISTS kg_cerdo NUMERIC(12,2) NOT NULL DEFAULT 0;
