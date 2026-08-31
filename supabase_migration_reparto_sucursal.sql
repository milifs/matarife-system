-- ============================================================
-- MIGRACIÓN: columna 'sucursal' en reparto_items (v18.25)
-- ============================================================
-- Texto libre (opcional) para aclarar a qué sucursal del cliente va cada
-- media. Junto con permitir el mismo cliente más de una vez en la lista,
-- deja armar una fila por sucursal.
-- ============================================================

ALTER TABLE reparto_items
  ADD COLUMN IF NOT EXISTS sucursal TEXT NOT NULL DEFAULT '';
