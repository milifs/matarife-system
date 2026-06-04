-- Agrega columna registrado_por a la tabla pagos
-- Guarda el nombre completo del usuario que registró el pago

ALTER TABLE pagos
  ADD COLUMN IF NOT EXISTS registrado_por TEXT;
