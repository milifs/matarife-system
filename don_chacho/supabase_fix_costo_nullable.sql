-- ════════════════════════════════════════════════════════════
-- FIX: columna costo_por_kg (vieja) era NOT NULL
-- ════════════════════════════════════════════════════════════
-- En Fase 2 dividimos el costo en novillo/cerdo. La columna vieja
-- quedó en la DB pero ya no se usa. Como sigue siendo NOT NULL,
-- cualquier INSERT/UPDATE falla.
--
-- Solución: permitir NULL en la columna vieja (mantenemos por
-- compatibilidad, no la borramos por si hay datos viejos).

ALTER TABLE costos_semana
ALTER COLUMN costo_por_kg DROP NOT NULL;

-- Darle un default de 0 por si algún código viejo todavía la escribe
ALTER TABLE costos_semana
ALTER COLUMN costo_por_kg SET DEFAULT 0;
