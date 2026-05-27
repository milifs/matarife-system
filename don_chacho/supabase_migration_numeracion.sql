-- ============================================================
-- GRANJA DON CHACHO - Migración: Numeración de remitos y pagos
-- Ejecutar en Supabase SQL Editor
-- ============================================================

-- Agregar campo numero a remitos
ALTER TABLE remitos ADD COLUMN IF NOT EXISTS numero INTEGER DEFAULT 0;

-- Agregar campo numero a pagos
ALTER TABLE pagos ADD COLUMN IF NOT EXISTS numero INTEGER DEFAULT 0;

-- Asignar números a remitos existentes (por orden de creación)
WITH numbered AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY creado_en ASC) as rn
  FROM remitos
)
UPDATE remitos SET numero = numbered.rn
FROM numbered WHERE remitos.id = numbered.id AND remitos.numero = 0;

-- Asignar números a pagos existentes (por orden de creación)
WITH numbered AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY creado_en ASC) as rn
  FROM pagos
)
UPDATE pagos SET numero = numbered.rn
FROM numbered WHERE pagos.id = numbered.id AND pagos.numero = 0;
