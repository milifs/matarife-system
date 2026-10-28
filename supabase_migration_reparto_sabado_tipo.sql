-- ============================================================
-- MIGRACIÓN: sábado + tipo de fila en la lista de reparto (v19.11)
-- ============================================================
-- Dos cambios en el módulo logístico de reparto:
--
-- 1. El reparto ahora también se hace el SÁBADO (antes solo jueves y
--    viernes). Se guarda sin acento ('sabado'), igual que el resto de los
--    valores de la columna, que son todos minúscula sin tildes.
--
-- 2. Cada fila pasa a pertenecer a UNA tabla: la de CARNE o la de CERDO.
--    La pantalla dejó de ser una grilla con dos columnas y ahora son dos
--    tablas separadas, así que una fila sin medias cargadas todavía (el
--    cliente recién agregado) necesita saber de qué tabla es; con solo
--    medias_carne / medias_cerdo en cero eso no se podía saber al releer.
--    Las columnas viejas se mantienen: la de 'carne' usa medias_carne y la
--    de 'cerdo' usa medias_cerdo, y la otra queda en 0.
-- ============================================================

-- ── 1. Sábado ───────────────────────────────────────────────
ALTER TABLE reparto_listas DROP CONSTRAINT IF EXISTS reparto_listas_dia_check;

ALTER TABLE reparto_listas
  ADD CONSTRAINT reparto_listas_dia_check
  CHECK (dia IN ('jueves', 'viernes', 'sabado'));

-- ── 2. Tipo de fila ─────────────────────────────────────────
ALTER TABLE reparto_items
  ADD COLUMN IF NOT EXISTS tipo TEXT NOT NULL DEFAULT 'carne';

ALTER TABLE reparto_items DROP CONSTRAINT IF EXISTS reparto_items_tipo_check;

ALTER TABLE reparto_items
  ADD CONSTRAINT reparto_items_tipo_check
  CHECK (tipo IN ('carne', 'cerdo'));

-- Backfill: las filas viejas traen las dos mercaderías juntas.
-- a) Las que tienen carne Y cerdo se parten en dos: la fila original se
--    queda con la carne y se crea una nueva con el cerdo.
INSERT INTO reparto_items
  (lista_id, cliente_id, medias_carne, medias_cerdo, sucursal, orden, tipo)
SELECT lista_id, cliente_id, 0, medias_cerdo, sucursal, orden, 'cerdo'
FROM reparto_items
WHERE medias_carne > 0 AND medias_cerdo > 0;

UPDATE reparto_items
SET medias_cerdo = 0
WHERE medias_carne > 0 AND medias_cerdo > 0;

-- b) Las que son solo de cerdo quedan marcadas como tales.
UPDATE reparto_items
SET tipo = 'cerdo'
WHERE medias_cerdo > 0 AND medias_carne = 0;
