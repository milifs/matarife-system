-- ============================================================
-- GRANJA DON CHACHO - Migración Fase 2
-- Ejecutar en Supabase SQL Editor DESPUÉS del schema original
-- ============================================================

-- Agregar campos de ubicación a clientes
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS ubicacion TEXT DEFAULT '';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS ubicacion_url TEXT DEFAULT '';

-- Modificar costos_semana para tener costo por tipo de carne
ALTER TABLE costos_semana ADD COLUMN IF NOT EXISTS costo_por_kg_novillo NUMERIC(10,2) DEFAULT 0;
ALTER TABLE costos_semana ADD COLUMN IF NOT EXISTS costo_por_kg_cerdo NUMERIC(10,2) DEFAULT 0;

-- Migrar datos existentes (si hay costo_por_kg viejo, copiarlo a novillo)
UPDATE costos_semana 
SET costo_por_kg_novillo = costo_por_kg 
WHERE costo_por_kg_novillo = 0 AND costo_por_kg > 0;
