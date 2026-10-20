-- ============================================================
-- v19.1 — Tipo de animal del proveedor (novillo / cerdo)
-- ============================================================
-- Cada proveedor vende una cosa u otra. Se guarda en el proveedor y no en
-- la carga a propósito: la especie no cambia semana a semana como el precio,
-- así que si alguna vez se cargó mal, corregir el proveedor tiene que
-- arreglar también las cargas viejas. Si un proveedor llegara a vender las
-- dos cosas, se crean dos proveedores.
--
-- Para qué: el módulo de ganancia va a separar costo/kg novillo de
-- costo/kg cerdo (ya existen esas dos columnas en `costos_semanales`,
-- hoy cargadas a mano desde la pantalla de inicio).
--
-- Se puede correr más de una vez sin romper nada.
-- ============================================================

-- 1) La columna. Default 'novillo' porque es lo que más se compra y así las
--    filas que ya existen quedan con un valor válido.
ALTER TABLE proveedores
  ADD COLUMN IF NOT EXISTS tipo TEXT NOT NULL DEFAULT 'novillo';

-- 2) Solo dos valores posibles. Mismo vocabulario en minúscula que usa
--    `carga_pagos.medio` (efectivo / transferencia / cheque).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'proveedores_tipo_check'
  ) THEN
    ALTER TABLE proveedores
      ADD CONSTRAINT proveedores_tipo_check
      CHECK (tipo IN ('novillo', 'cerdo'));
  END IF;
END $$;

-- 3) Índice: el módulo de ganancia va a agrupar las cargas por tipo.
CREATE INDEX IF NOT EXISTS idx_proveedores_tipo ON proveedores(tipo);
