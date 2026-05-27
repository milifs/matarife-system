-- ═══════════════════════════════════════════════════════════
-- Migration v14: Fix costo_por_kg NOT NULL constraint
-- ═══════════════════════════════════════════════════════════
-- Problema: la columna vieja costo_por_kg sigue siendo NOT NULL,
-- pero ahora guardamos costo_por_kg_novillo y costo_por_kg_cerdo
-- por separado. Al intentar insertar un nuevo costo semanal falla.

-- Hacer la columna vieja nullable (la dejamos por compatibilidad)
ALTER TABLE costos_semana
ALTER COLUMN costo_por_kg DROP NOT NULL;

-- Y le ponemos default 0 por si algún insert viejo la necesita
ALTER TABLE costos_semana
ALTER COLUMN costo_por_kg SET DEFAULT 0;
