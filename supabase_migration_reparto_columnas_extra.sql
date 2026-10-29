-- ============================================================
-- MIGRACIÓN: columnas extra en la lista de reparto (v19.13)
-- ============================================================
-- A veces Joaco vende algo que no es una media: una pierna, grasa, lo que
-- aparezca esa semana. Hasta ahora no tenía dónde anotarlo y quedaba en las
-- notas sueltas, sin cantidad por cliente.
--
-- Cada tabla (la de carne y la de cerdo, de cada día) puede sumar hasta DOS
-- columnas más al final, con el encabezado escrito a mano.
--
-- Va en JSONB y no en tablas nuevas: son como mucho dos columnas por tabla,
-- sin vida propia (no se consultan, no se cruzan con nada, no tienen que
-- existir si nadie las usa). El mismo criterio que `kgs_por_media`.
-- ============================================================

-- Los nombres de las columnas, por mercadería:
--   {"carne": ["Pierna", "Grasa"], "cerdo": []}
-- El ORDEN del array es la posición de la columna en la grilla.
ALTER TABLE reparto_listas
  ADD COLUMN IF NOT EXISTS columnas_extra JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Lo que lleva cada cliente en esas columnas, en el mismo orden:
--   [2, 0]  -> 2 de la primera columna, nada de la segunda
-- Es un array y no un objeto con el nombre adentro a propósito: así
-- renombrar el encabezado no pierde los números que ya estaban cargados.
ALTER TABLE reparto_items
  ADD COLUMN IF NOT EXISTS extras JSONB NOT NULL DEFAULT '[]'::jsonb;
