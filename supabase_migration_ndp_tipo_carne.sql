-- v18.19 — Campo tipo_carne separado de descripcion en notas de pedido
-- Antes (v18.17) el tipo de carne se guardaba en la columna `descripcion`.
-- Ahora hay dos campos: `tipo_carne` (dropdown) y `descripcion` (texto libre).

-- 1) Nueva columna
ALTER TABLE nota_pedido_items
  ADD COLUMN IF NOT EXISTS tipo_carne TEXT DEFAULT '';

-- 2) Backfill de las NDP v18.17: si la descripcion es uno de los tipos del
--    catálogo, se mueve a tipo_carne y se vacía la descripcion (era el tipo,
--    no texto libre). Las NDP viejas de texto libre (ej. "EL DORADO-novillo")
--    quedan intactas: tipo_carne vacío, descripcion conservada.
UPDATE nota_pedido_items
SET tipo_carne = descripcion,
    descripcion = ''
WHERE descripcion IN (
  'Novillo', 'Cerdo', 'Pierna mocha', 'Pierna pistola',
  'Plancha de asado', 'Octavo', '1/4 delantero'
);
