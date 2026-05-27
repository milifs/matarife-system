-- Migración: hacer costo_por_kg nullable
-- Desde la Fase 2 dividimos el costo en novillo y cerdo
-- La columna original costo_por_kg sigue en la tabla pero ya no se usa

ALTER TABLE costos_semana 
  ALTER COLUMN costo_por_kg DROP NOT NULL;

-- También podemos ponerle default 0 por si alguna query vieja la usa
ALTER TABLE costos_semana 
  ALTER COLUMN costo_por_kg SET DEFAULT 0;
