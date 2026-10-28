-- RESET DEL DEPÓSITO — deja el módulo en cero para empezar la carga de nuevo
--
-- CORRER UNA SOLA VEZ, Y DESPUÉS DE `supabase_migration_deposito_arranque_kg.sql`
-- (este script escribe las columnas de kg del arranque).
--
-- QUÉ BORRA
--   · Todos los movimientos de depósito (entradas, salidas y recuentos).
--   · La auditoría de movimientos borrados: lo de antes era carga de prueba,
--     no historia que valga la pena guardar.
--   · El arranque queda en 0 medias / 0 kg y con fecha de HOY.
--
-- QUÉ NO TOCA
--   Remitos, cargas de proveedores, clientes ni pagos. El depósito no guarda
--   stock: lo deriva de esas tablas. Por eso alcanza con mover la FECHA DE
--   ARRANQUE: todo lo anterior a hoy deja de contar sin borrar un solo remito.
--
-- OJO CON LOS REMITOS DE HOY: la ecuación cuenta los remitos confirmados
-- desde `fecha_inicio` INCLUSIVE. Si hoy ya se cargó alguno, va a aparecer
-- restando apenas se fije el arranque. Para arrancar realmente limpio desde
-- mañana, cambiá `CURRENT_DATE` por `CURRENT_DATE + 1` en el UPDATE de abajo.

BEGIN;

DELETE FROM deposito_movimientos;
DELETE FROM deposito_movimientos_eliminados;

-- El arranque es una sola fila (columna `unica`), así que el UPDATE sin WHERE
-- toca exactamente esa. Si todavía no existe, no actualiza nada y el arranque
-- se carga desde la app.
UPDATE deposito_config
SET medias_novillo = 0,
    medias_cerdo   = 0,
    kg_novillo     = 0,
    kg_cerdo       = 0,
    fecha_inicio   = CURRENT_DATE,
    actualizado_en = now();

COMMIT;

-- Para verificar que quedó en cero:
-- SELECT * FROM deposito_config;
-- SELECT count(*) FROM deposito_movimientos;
