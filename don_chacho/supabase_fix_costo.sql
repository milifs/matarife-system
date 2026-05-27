-- Fix: hacer la columna costo_por_kg nullable (quedó de la Fase 1, ahora no se usa)
-- Ya que costo_por_kg fue reemplazado por costo_por_kg_novillo y costo_por_kg_cerdo

ALTER TABLE costos_semana 
  ALTER COLUMN costo_por_kg DROP NOT NULL;

-- Opcional: también podés poner default en 0 si querés más seguridad
ALTER TABLE costos_semana 
  ALTER COLUMN costo_por_kg SET DEFAULT 0;
