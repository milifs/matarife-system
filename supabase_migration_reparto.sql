-- ============================================================
-- MIGRACIÓN: Listas de reparto de carne (logística semanal)
-- ============================================================
-- Módulo independiente de lo comercial: NO toca saldos, remitos ni pagos.
-- Cada semana tiene dos listas (jueves / viernes). Cada lista tiene filas
-- por cliente con la cantidad de medias de CARNE (novillo) y CERDO.
-- El TOTAL MEDIAS se carga a mano; el SOBRANTE = total - repartido (en la app).
-- ============================================================

CREATE TABLE IF NOT EXISTS reparto_listas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  semana_inicio DATE NOT NULL,               -- lunes de la semana
  dia TEXT NOT NULL CHECK (dia IN ('jueves', 'viernes')),
  total_medias_carne INT NOT NULL DEFAULT 0, -- cargado manualmente
  total_medias_cerdo INT NOT NULL DEFAULT 0, -- cargado manualmente
  notas TEXT NOT NULL DEFAULT '',
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (semana_inicio, dia)
);

CREATE TABLE IF NOT EXISTS reparto_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lista_id UUID NOT NULL REFERENCES reparto_listas(id) ON DELETE CASCADE,
  cliente_id UUID NOT NULL REFERENCES clientes(id),
  medias_carne INT NOT NULL DEFAULT 0,
  medias_cerdo INT NOT NULL DEFAULT 0,
  orden INT NOT NULL DEFAULT 0,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reparto_items_lista ON reparto_items(lista_id);

-- Mismo criterio que el resto de las tablas de la app.
ALTER TABLE reparto_listas DISABLE ROW LEVEL SECURITY;
ALTER TABLE reparto_items DISABLE ROW LEVEL SECURITY;
