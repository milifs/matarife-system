-- ============================================================
-- MIGRACIÓN: las políticas de RLS (Fase 2) — NO CORRIDA TODAVÍA
-- ============================================================
-- Implementa la matriz de `auth_fase1_diseno.md` (punto 5). Requiere que la
-- Fase 1 esté corrida: todas las políticas de acá llaman a `es_admin()` y
-- `tiene_permiso()`, que crea `supabase_migration_auth_identidad.sql`.
--
-- ESTE ARCHIVO CREA LAS POLÍTICAS Y **NO ENCIENDE RLS EN NINGUNA TABLA**.
--
-- No es una formalidad: en Postgres, una política sobre una tabla con RLS
-- deshabilitado **existe y se ignora**. Eso permite exactamente lo que esta
-- fase necesita — dejar todo creado, verificarlo con el ensayo del punto 2.2
-- de `auth_fase1_staging.md`, y recién después encender tabla por tabla. El
-- bloque final tiene los `ENABLE` comentados, en el orden recomendado.
--
-- Todas las políticas son `TO authenticated`. Es el corazón del cambio: desde
-- el momento en que una tabla tenga RLS encendido, **la publishable key sola
-- (rol `anon`) no devuelve ninguna fila**. Hoy devuelve 108 clientes, 1871
-- pagos y 1087 remitos.
--
-- PREREQUISITOS (los tres, ver punto 6 del diseño):
--   1. `AppProvider.cargarDatos()` tiene que distinguir "sin permiso" de
--      "sin datos". Bajo RLS una tabla denegada vuelve VACÍA, no con error, y
--      `saldo = remitos − pagos` con `pagos` vacío infla todos los saldos.
--   2. `supabase_migration_soporte_reportado_por_id.sql` corrida (la política
--      de `soportes` de acá la necesita).
--   3. `AuthService.permitirLoginLegacy = false` deployado. Un login legacy
--      no abre sesión, así que `auth.uid()` es NULL y ese usuario vería todo
--      vacío.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- 1. Funciones auxiliares
-- ════════════════════════════════════════════════════════════
-- Mismos recaudos que las de la Fase 1 y por las mismas razones:
-- SECURITY DEFINER para que leer `usuarios` desde una política de otra tabla
-- no dispare la política de `usuarios` (recursión infinita), STABLE para que
-- Postgres las llame una vez por consulta y no una por fila, y search_path
-- fijo porque es obligatorio con SECURITY DEFINER.

-- ── es_usuario_activo() ─────────────────────────────────────
-- "Cualquiera que esté logueado" NO alcanza como permiso. Una cuenta de Auth
-- puede existir sin perfil activo: alguien a quien el admin dio de baja en
-- Gestión de Usuarios conserva su identidad de `auth.users` y sigue siendo
-- `authenticated` para Postgres. Si las tablas abiertas (clientes, reparto)
-- dijeran `USING (true)`, darlo de baja no le cortaría el acceso a los datos.
--
-- Esta función es la que hace que la baja signifique algo en la base.
CREATE OR REPLACE FUNCTION public.es_usuario_activo()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM usuarios u
    WHERE u.auth_id = auth.uid()
      AND u.activo
  );
$$;

COMMENT ON FUNCTION public.es_usuario_activo() IS
  'true si quien consulta tiene un perfil ACTIVO en usuarios. Una cuenta de '
  'Auth sin perfil activo (usuario dado de baja) devuelve false.';

-- ── puede_ver_saldo() ───────────────────────────────────────
-- La "regla del saldo" del punto 5.1 del diseño, en una sola función.
--
-- `saldo = remitos confirmados − pagos ± notas de crédito/débito`, así que
-- todo permiso que abra una pantalla donde se vea un saldo tiene que dar
-- lectura sobre las TRES tablas. Son cuatro permisos, y los dos últimos no
-- son obvios:
--   · ver_consultas         → el tab Saldos, Vencidos, Historial, Reporte
--   · crear_pago            → el formulario de pago muestra el saldo vencido
--   · gestionar_clientes    → la pestaña Clientes muestra el saldo EN PESOS
--                             de cada cliente (clientes_screen.dart:217)
--   · gestionar_vendedores  → la pestaña Vendedores, el de cada vendedor
--                             (vendedores_screen.dart:114)
--
-- Va como función con nombre y no como un OR repetido en seis políticas: el
-- día que aparezca una pantalla nueva con un saldo, se agrega el permiso acá
-- y no hay que acordarse de las seis.
--
-- Con los cuatro roles que existen hoy los dos últimos arms no cambian nada
-- (los tres roles que llegan a esas pestañas tienen además `ver_consultas`).
-- Están por los roles que el admin PUEDE armar: los roles son configurables
-- desde Gestión de Usuarios, y un rol con `gestionar_clientes` y sin
-- `ver_consultas` vería esa columna de pesos mal y sin aviso.
CREATE OR REPLACE FUNCTION public.puede_ver_saldo()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM usuarios u
    JOIN roles r ON r.id = u.rol_id
    WHERE u.auth_id = auth.uid()
      AND u.activo
      AND (
        r.es_admin
        OR EXISTS (
          SELECT 1 FROM rol_permisos rp
          WHERE rp.rol_id = r.id
            AND rp.permiso_id IN (
              'ver_consultas',
              'crear_pago',
              'gestionar_clientes',
              'gestionar_vendedores'
            )
        )
      )
  );
$$;

COMMENT ON FUNCTION public.puede_ver_saldo() IS
  'La regla del saldo: true si el rol tiene alguno de los permisos que abren '
  'una pantalla donde se ve un saldo. Da lectura sobre remitos, pagos y '
  'notas_credito_debito, que son las tres tablas de las que el saldo sale.';

GRANT EXECUTE ON FUNCTION public.es_usuario_activo() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.puede_ver_saldo() TO anon, authenticated;


-- ════════════════════════════════════════════════════════════
-- 2. Cómo leer lo que sigue
-- ════════════════════════════════════════════════════════════
-- · Una política por comando (SELECT / INSERT / UPDATE / DELETE). Postgres
--   pide `USING` para leer, modificar y borrar, y `WITH CHECK` para insertar.
-- · **Comando sin política = comando denegado**, para todos. Por eso las
--   tablas de auditoría no tienen política de UPDATE ni de DELETE: es la
--   forma de decir "nadie, el admin incluido", y no hace falta escribir un
--   `USING (false)`.
-- · Todas `TO authenticated`: `anon` no entra en ninguna.
-- · Los `DROP POLICY IF EXISTS` hacen que el archivo se pueda correr de nuevo
--   sin errores.


-- ════════════════════════════════════════════════════════════
-- 3. Circuito comercial
-- ════════════════════════════════════════════════════════════

-- ── vendedores ──────────────────────────────────────────────
-- Lectura para cualquier usuario activo: los nombres salen en los filtros de
-- media app y en la Lista de reparto, que no tiene gate a propósito.
DROP POLICY IF EXISTS vendedores_select ON vendedores;
CREATE POLICY vendedores_select ON vendedores FOR SELECT TO authenticated
  USING (es_usuario_activo());

DROP POLICY IF EXISTS vendedores_insert ON vendedores;
CREATE POLICY vendedores_insert ON vendedores FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_vendedores'));

DROP POLICY IF EXISTS vendedores_update ON vendedores;
CREATE POLICY vendedores_update ON vendedores FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_vendedores'))
  WITH CHECK (tiene_permiso('gestionar_vendedores'));

DROP POLICY IF EXISTS vendedores_delete ON vendedores;
CREATE POLICY vendedores_delete ON vendedores FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_vendedores'));

-- ── clientes ────────────────────────────────────────────────
-- Misma razón que vendedores: el reparto es para todos y necesita los nombres.
DROP POLICY IF EXISTS clientes_select ON clientes;
CREATE POLICY clientes_select ON clientes FOR SELECT TO authenticated
  USING (es_usuario_activo());

DROP POLICY IF EXISTS clientes_insert ON clientes;
CREATE POLICY clientes_insert ON clientes FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_clientes'));

DROP POLICY IF EXISTS clientes_update ON clientes;
CREATE POLICY clientes_update ON clientes FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_clientes'))
  WITH CHECK (tiene_permiso('gestionar_clientes'));

DROP POLICY IF EXISTS clientes_delete ON clientes;
CREATE POLICY clientes_delete ON clientes FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_clientes'));

-- ── remitos ─────────────────────────────────────────────────
-- `ver_kg_semana` (v19.17) está en el SELECT porque los kg de la semana del
-- Inicio salen de `remito_items`. Hoy no cambia nada —el único rol que lo
-- tiene, Secretaria, ya leía remitos por `crear_remito`— pero cubre al rol
-- que el admin puede armar con ese permiso solo.
--
-- El INSERT va `crear_remito OR confirmar_remito` y no solo `crear_remito`:
-- confirmar una Nota de Pedido **crea un remito** (`confirmarNotaPedido`), así
-- que un rol que pudiera confirmar sin poder crear no podría confirmar nada.
-- Hoy el único que confirma es el admin, que tiene los dos permisos, pero los
-- roles son configurables.
DROP POLICY IF EXISTS remitos_select ON remitos;
CREATE POLICY remitos_select ON remitos FOR SELECT TO authenticated
  USING (puede_ver_saldo() OR tiene_permiso('crear_remito') OR tiene_permiso('ver_kg_semana'));

DROP POLICY IF EXISTS remitos_insert ON remitos;
CREATE POLICY remitos_insert ON remitos FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('crear_remito') OR tiene_permiso('confirmar_remito'));

DROP POLICY IF EXISTS remitos_update ON remitos;
CREATE POLICY remitos_update ON remitos FOR UPDATE TO authenticated
  USING (tiene_permiso('editar_remito') OR tiene_permiso('confirmar_remito'))
  WITH CHECK (tiene_permiso('editar_remito') OR tiene_permiso('confirmar_remito'));

DROP POLICY IF EXISTS remitos_delete ON remitos;
CREATE POLICY remitos_delete ON remitos FOR DELETE TO authenticated
  USING (tiene_permiso('eliminar_remito'));

-- ── remito_items ────────────────────────────────────────────
-- Siguen a su remito: los ítems no tienen vida propia. El DELETE es el de
-- `eliminar_remito` porque borrar un remito se lleva sus ítems, y además
-- editar un remito reemplaza los ítems (delete + insert), de ahí el
-- `editar_remito` en el DELETE.
DROP POLICY IF EXISTS remito_items_select ON remito_items;
CREATE POLICY remito_items_select ON remito_items FOR SELECT TO authenticated
  USING (puede_ver_saldo() OR tiene_permiso('crear_remito') OR tiene_permiso('ver_kg_semana'));

DROP POLICY IF EXISTS remito_items_insert ON remito_items;
CREATE POLICY remito_items_insert ON remito_items FOR INSERT TO authenticated
  WITH CHECK (
    tiene_permiso('crear_remito')
    OR tiene_permiso('confirmar_remito')
    OR tiene_permiso('editar_remito')
  );

DROP POLICY IF EXISTS remito_items_update ON remito_items;
CREATE POLICY remito_items_update ON remito_items FOR UPDATE TO authenticated
  USING (tiene_permiso('editar_remito'))
  WITH CHECK (tiene_permiso('editar_remito'));

DROP POLICY IF EXISTS remito_items_delete ON remito_items;
CREATE POLICY remito_items_delete ON remito_items FOR DELETE TO authenticated
  USING (tiene_permiso('eliminar_remito') OR tiene_permiso('editar_remito'));

-- ── pagos ───────────────────────────────────────────────────
-- **Sin política de UPDATE a propósito**: los pagos NO se pueden editar
-- (editarlos generaba errores de saldo, está en CLAUDE.md). La pantalla solo
-- permite ver y eliminar, y la base ahora dice lo mismo.
DROP POLICY IF EXISTS pagos_select ON pagos;
CREATE POLICY pagos_select ON pagos FOR SELECT TO authenticated
  USING (puede_ver_saldo());

DROP POLICY IF EXISTS pagos_insert ON pagos;
CREATE POLICY pagos_insert ON pagos FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('crear_pago'));

DROP POLICY IF EXISTS pagos_delete ON pagos;
CREATE POLICY pagos_delete ON pagos FOR DELETE TO authenticated
  USING (tiene_permiso('editar_pago'));

-- ── pago_medios ─────────────────────────────────────────────
DROP POLICY IF EXISTS pago_medios_select ON pago_medios;
CREATE POLICY pago_medios_select ON pago_medios FOR SELECT TO authenticated
  USING (puede_ver_saldo());

DROP POLICY IF EXISTS pago_medios_insert ON pago_medios;
CREATE POLICY pago_medios_insert ON pago_medios FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('crear_pago'));

DROP POLICY IF EXISTS pago_medios_delete ON pago_medios;
CREATE POLICY pago_medios_delete ON pago_medios FOR DELETE TO authenticated
  USING (tiene_permiso('editar_pago'));

-- ── notas_credito_debito ────────────────────────────────────
-- Mueven el saldo de un cliente igual que un pago, así que van con los mismos
-- permisos. El gate de la pantalla es `crear_pago` desde v19.14.
DROP POLICY IF EXISTS notas_cd_select ON notas_credito_debito;
CREATE POLICY notas_cd_select ON notas_credito_debito FOR SELECT TO authenticated
  USING (puede_ver_saldo());

DROP POLICY IF EXISTS notas_cd_insert ON notas_credito_debito;
CREATE POLICY notas_cd_insert ON notas_credito_debito FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('crear_pago'));

DROP POLICY IF EXISTS notas_cd_delete ON notas_credito_debito;
CREATE POLICY notas_cd_delete ON notas_credito_debito FOR DELETE TO authenticated
  USING (tiene_permiso('editar_pago'));

-- ── notas_pedido ────────────────────────────────────────────
-- Acá NO se usa `puede_ver_saldo()` y es deliberado: una NDP pendiente **no
-- afecta el saldo** (solo los remitos confirmados cuentan), así que no es una
-- de las tablas de las que el saldo está hecho. Los permisos son los de la
-- bandeja y del formulario.
DROP POLICY IF EXISTS notas_pedido_select ON notas_pedido;
CREATE POLICY notas_pedido_select ON notas_pedido FOR SELECT TO authenticated
  USING (
    tiene_permiso('ver_consultas')
    OR tiene_permiso('crear_remito')
    OR tiene_permiso('confirmar_remito')
  );

DROP POLICY IF EXISTS notas_pedido_insert ON notas_pedido;
CREATE POLICY notas_pedido_insert ON notas_pedido FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('crear_remito'));

DROP POLICY IF EXISTS notas_pedido_update ON notas_pedido;
CREATE POLICY notas_pedido_update ON notas_pedido FOR UPDATE TO authenticated
  USING (tiene_permiso('editar_remito') OR tiene_permiso('confirmar_remito'))
  WITH CHECK (tiene_permiso('editar_remito') OR tiene_permiso('confirmar_remito'));

DROP POLICY IF EXISTS notas_pedido_delete ON notas_pedido;
CREATE POLICY notas_pedido_delete ON notas_pedido FOR DELETE TO authenticated
  USING (tiene_permiso('editar_remito'));

-- ── nota_pedido_items ───────────────────────────────────────
-- Editar una NDP reemplaza los ítems (delete + insert), de ahí los permisos
-- de edición en el INSERT y en el DELETE.
DROP POLICY IF EXISTS nota_pedido_items_select ON nota_pedido_items;
CREATE POLICY nota_pedido_items_select ON nota_pedido_items FOR SELECT TO authenticated
  USING (
    tiene_permiso('ver_consultas')
    OR tiene_permiso('crear_remito')
    OR tiene_permiso('confirmar_remito')
  );

DROP POLICY IF EXISTS nota_pedido_items_insert ON nota_pedido_items;
CREATE POLICY nota_pedido_items_insert ON nota_pedido_items FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('crear_remito') OR tiene_permiso('editar_remito'));

DROP POLICY IF EXISTS nota_pedido_items_delete ON nota_pedido_items;
CREATE POLICY nota_pedido_items_delete ON nota_pedido_items FOR DELETE TO authenticated
  USING (tiene_permiso('editar_remito'));

-- ── costos_semana ───────────────────────────────────────────
-- La lectura va con el permiso de escritura, sin arm aparte: el costo por kg
-- ES el margen del negocio, y las dos pantallas que lo usan (el dashboard y
-- Ganancias) ya son solo del dueño desde v19.14.
--
-- OJO, caso de 6.1: `cargarDatos()` pide los costos para TODOS los roles. Al
-- encender esta tabla, a los demás les van a volver vacíos y `costoParaFecha`
-- va a devolver null — hoy eso no se ve en ninguna pantalla de un no-admin,
-- pero es la misma trampa que los saldos.
DROP POLICY IF EXISTS costos_semana_select ON costos_semana;
CREATE POLICY costos_semana_select ON costos_semana FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_costos'));

DROP POLICY IF EXISTS costos_semana_insert ON costos_semana;
CREATE POLICY costos_semana_insert ON costos_semana FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_costos'));

DROP POLICY IF EXISTS costos_semana_update ON costos_semana;
CREATE POLICY costos_semana_update ON costos_semana FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_costos'))
  WITH CHECK (tiene_permiso('gestionar_costos'));

DROP POLICY IF EXISTS costos_semana_delete ON costos_semana;
CREATE POLICY costos_semana_delete ON costos_semana FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_costos'));


-- ════════════════════════════════════════════════════════════
-- 4. Compras a proveedores y depósito
-- ════════════════════════════════════════════════════════════
-- **Estas políticas suponen el depósito de la PR #20** ("el depósito es el
-- registro de lo que hay, no se reconcilia contra remitos"), **mergeada a
-- master el 29/10/2026**. Ahí
-- `cargarDeposito` pasó a leer solo `deposito_config` y
-- `deposito_movimientos`: ya no lee `cargas`, ni `proveedores`, ni `remitos`.
--
-- Por eso `gestionar_deposito` **no** aparece como arm de lectura en
-- `proveedores`, `cargas`, `remitos` ni `remito_items`. Es un recorte real:
-- el Encargado de Depósito queda sin acceso a nada del circuito comercial.
--
-- **Si alguna vez el depósito volviera a reconciliarse contra remitos**, hay
-- que volver a agregar esos cuatro arms, o el módulo se rompe (el stock no
-- podría leer las cargas ni los remitos):
--   ALTER POLICY proveedores_select  ON proveedores  USING (tiene_permiso('gestionar_proveedores') OR tiene_permiso('gestionar_deposito'));
--   ALTER POLICY cargas_select       ON cargas       USING (tiene_permiso('gestionar_proveedores') OR tiene_permiso('gestionar_deposito'));
--   ALTER POLICY remitos_select      ON remitos      USING (puede_ver_saldo() OR tiene_permiso('crear_remito') OR tiene_permiso('gestionar_deposito'));
--   ALTER POLICY remito_items_select ON remito_items USING (puede_ver_saldo() OR tiene_permiso('crear_remito') OR tiene_permiso('gestionar_deposito'));

-- ── proveedores ─────────────────────────────────────────────
DROP POLICY IF EXISTS proveedores_select ON proveedores;
CREATE POLICY proveedores_select ON proveedores FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS proveedores_insert ON proveedores;
CREATE POLICY proveedores_insert ON proveedores FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS proveedores_update ON proveedores;
CREATE POLICY proveedores_update ON proveedores FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_proveedores'))
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS proveedores_delete ON proveedores;
CREATE POLICY proveedores_delete ON proveedores FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

-- ── cargas ──────────────────────────────────────────────────
DROP POLICY IF EXISTS cargas_select ON cargas;
CREATE POLICY cargas_select ON cargas FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS cargas_insert ON cargas;
CREATE POLICY cargas_insert ON cargas FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS cargas_update ON cargas;
CREATE POLICY cargas_update ON cargas FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_proveedores'))
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS cargas_delete ON cargas;
CREATE POLICY cargas_delete ON cargas FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

-- ── carga_pagos ─────────────────────────────────────────────
DROP POLICY IF EXISTS carga_pagos_select ON carga_pagos;
CREATE POLICY carga_pagos_select ON carga_pagos FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS carga_pagos_insert ON carga_pagos;
CREATE POLICY carga_pagos_insert ON carga_pagos FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS carga_pagos_update ON carga_pagos;
CREATE POLICY carga_pagos_update ON carga_pagos FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_proveedores'))
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS carga_pagos_delete ON carga_pagos;
CREATE POLICY carga_pagos_delete ON carga_pagos FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

-- ── deposito_config ─────────────────────────────────────────
-- Sin política de DELETE: es una sola fila (el truco de `unica`) que se
-- upsertea, no se borra nunca.
DROP POLICY IF EXISTS deposito_config_select ON deposito_config;
CREATE POLICY deposito_config_select ON deposito_config FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_deposito'));

DROP POLICY IF EXISTS deposito_config_insert ON deposito_config;
CREATE POLICY deposito_config_insert ON deposito_config FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_deposito'));

DROP POLICY IF EXISTS deposito_config_update ON deposito_config;
CREATE POLICY deposito_config_update ON deposito_config FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_deposito'))
  WITH CHECK (tiene_permiso('gestionar_deposito'));

-- ── deposito_movimientos ────────────────────────────────────
DROP POLICY IF EXISTS deposito_movimientos_select ON deposito_movimientos;
CREATE POLICY deposito_movimientos_select ON deposito_movimientos FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_deposito'));

DROP POLICY IF EXISTS deposito_movimientos_insert ON deposito_movimientos;
CREATE POLICY deposito_movimientos_insert ON deposito_movimientos FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_deposito'));

DROP POLICY IF EXISTS deposito_movimientos_update ON deposito_movimientos;
CREATE POLICY deposito_movimientos_update ON deposito_movimientos FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_deposito'))
  WITH CHECK (tiene_permiso('gestionar_deposito'));

DROP POLICY IF EXISTS deposito_movimientos_delete ON deposito_movimientos;
CREATE POLICY deposito_movimientos_delete ON deposito_movimientos FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_deposito'));


-- ════════════════════════════════════════════════════════════
-- 5. Auditoría: se escribe una vez y no se toca nunca más
-- ════════════════════════════════════════════════════════════
-- Ninguna de estas tablas tiene política de UPDATE ni de DELETE, **el admin
-- incluido**. Una auditoría que se puede editar no es una auditoría: el
-- módulo de depósito existe justamente porque una media res salió de la
-- cámara y nadie pudo decir dónde estaba, y el rastro de los borrados es lo
-- que contesta esa pregunta.
--
-- Si algún día hay que limpiar una fila, se hace por SQL desde el dashboard
-- (que corre como `postgres` y saltea RLS) y queda registrado ahí.
--
-- El permiso de INSERT es el mismo que el del borrado que la genera: no se
-- puede escribir una fila de auditoría de algo que no se podía borrar.

DROP POLICY IF EXISTS remitos_eliminados_select ON remitos_eliminados;
CREATE POLICY remitos_eliminados_select ON remitos_eliminados FOR SELECT TO authenticated
  USING (tiene_permiso('ver_consultas'));

DROP POLICY IF EXISTS remitos_eliminados_insert ON remitos_eliminados;
CREATE POLICY remitos_eliminados_insert ON remitos_eliminados FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('eliminar_remito'));

DROP POLICY IF EXISTS pagos_eliminados_select ON pagos_eliminados;
CREATE POLICY pagos_eliminados_select ON pagos_eliminados FOR SELECT TO authenticated
  USING (tiene_permiso('ver_consultas'));

DROP POLICY IF EXISTS pagos_eliminados_insert ON pagos_eliminados;
CREATE POLICY pagos_eliminados_insert ON pagos_eliminados FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('editar_pago'));

DROP POLICY IF EXISTS notas_pedido_eliminadas_select ON notas_pedido_eliminadas;
CREATE POLICY notas_pedido_eliminadas_select ON notas_pedido_eliminadas FOR SELECT TO authenticated
  USING (tiene_permiso('ver_consultas'));

DROP POLICY IF EXISTS notas_pedido_eliminadas_insert ON notas_pedido_eliminadas;
CREATE POLICY notas_pedido_eliminadas_insert ON notas_pedido_eliminadas FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('editar_remito'));

DROP POLICY IF EXISTS notas_cd_eliminadas_select ON notas_cd_eliminadas;
CREATE POLICY notas_cd_eliminadas_select ON notas_cd_eliminadas FOR SELECT TO authenticated
  USING (tiene_permiso('ver_consultas'));

DROP POLICY IF EXISTS notas_cd_eliminadas_insert ON notas_cd_eliminadas;
CREATE POLICY notas_cd_eliminadas_insert ON notas_cd_eliminadas FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('editar_pago'));

DROP POLICY IF EXISTS cargas_eliminadas_select ON cargas_eliminadas;
CREATE POLICY cargas_eliminadas_select ON cargas_eliminadas FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS cargas_eliminadas_insert ON cargas_eliminadas;
CREATE POLICY cargas_eliminadas_insert ON cargas_eliminadas FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS carga_pagos_eliminados_select ON carga_pagos_eliminados;
CREATE POLICY carga_pagos_eliminados_select ON carga_pagos_eliminados FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS carga_pagos_eliminados_insert ON carga_pagos_eliminados;
CREATE POLICY carga_pagos_eliminados_insert ON carga_pagos_eliminados FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_proveedores'));

DROP POLICY IF EXISTS deposito_mov_eliminados_select ON deposito_movimientos_eliminados;
CREATE POLICY deposito_mov_eliminados_select ON deposito_movimientos_eliminados
  FOR SELECT TO authenticated
  USING (tiene_permiso('gestionar_deposito'));

DROP POLICY IF EXISTS deposito_mov_eliminados_insert ON deposito_movimientos_eliminados;
CREATE POLICY deposito_mov_eliminados_insert ON deposito_movimientos_eliminados
  FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_deposito'));


-- ════════════════════════════════════════════════════════════
-- 6. Logística, soporte y el propio sistema de permisos
-- ════════════════════════════════════════════════════════════

-- ── reparto_listas / reparto_items ──────────────────────────
-- Abiertas a cualquier usuario activo, a propósito: es logística sin plata y
-- hoy no tienen gate de UI. La política no inventa un permiso que la app no
-- pide — solo exige estar logueado y activo.
DROP POLICY IF EXISTS reparto_listas_all ON reparto_listas;
CREATE POLICY reparto_listas_all ON reparto_listas FOR ALL TO authenticated
  USING (es_usuario_activo())
  WITH CHECK (es_usuario_activo());

DROP POLICY IF EXISTS reparto_items_all ON reparto_items;
CREATE POLICY reparto_items_all ON reparto_items FOR ALL TO authenticated
  USING (es_usuario_activo())
  WITH CHECK (es_usuario_activo());

-- ── soportes ────────────────────────────────────────────────
-- **Requiere `supabase_migration_soporte_reportado_por_id.sql`.** La columna
-- vieja `reportado_por` es TEXT con el nombre completo, y una política no se
-- puede apoyar en eso: `nombre_completo` no es único, renombrar a alguien le
-- borraría su historia de tickets, y el match depende de tildes y mayúsculas
-- ("soledad Alcalá").
--
-- Cada uno ve lo suyo; el admin ve todo (es el que atiende la bandeja).
DROP POLICY IF EXISTS soportes_select ON soportes;
CREATE POLICY soportes_select ON soportes FOR SELECT TO authenticated
  USING (
    es_admin()
    OR reportado_por_id IN (
      SELECT u.id FROM usuarios u WHERE u.auth_id = auth.uid()
    )
  );

-- El WITH CHECK ata el ticket a quien lo escribe: nadie puede abrir un
-- reclamo a nombre de otro.
DROP POLICY IF EXISTS soportes_insert ON soportes;
CREATE POLICY soportes_insert ON soportes FOR INSERT TO authenticated
  WITH CHECK (
    es_usuario_activo()
    AND reportado_por_id IN (
      SELECT u.id FROM usuarios u WHERE u.auth_id = auth.uid()
    )
  );

-- Responder y cambiar el estado es de la bandeja de triage, que ya es solo
-- del admin. Sin política de DELETE: un reclamo no se borra.
DROP POLICY IF EXISTS soportes_update ON soportes;
CREATE POLICY soportes_update ON soportes FOR UPDATE TO authenticated
  USING (es_admin())
  WITH CHECK (es_admin());

-- ── permisos ────────────────────────────────────────────────
-- Catálogo fijo de 14. Lectura para cualquier usuario activo (Gestión de
-- Usuarios arma los checkboxes con esto) y **ninguna política de escritura**:
-- el catálogo se toca por SQL, como se tocó al agregar `gestionar_proveedores`
-- y `gestionar_deposito`.
DROP POLICY IF EXISTS permisos_select ON permisos;
CREATE POLICY permisos_select ON permisos FOR SELECT TO authenticated
  USING (es_usuario_activo());

-- ── roles / rol_permisos ────────────────────────────────────
-- La lectura tiene que ser abierta a cualquier usuario activo: al entrar, la
-- app carga SU PROPIO rol y sus permisos (`AuthService._cargarRol`). Si esto
-- fuera solo para `gestionar_usuarios`, nadie salvo el admin podría loguearse.
DROP POLICY IF EXISTS roles_select ON roles;
CREATE POLICY roles_select ON roles FOR SELECT TO authenticated
  USING (es_usuario_activo());

DROP POLICY IF EXISTS roles_insert ON roles;
CREATE POLICY roles_insert ON roles FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_usuarios'));

DROP POLICY IF EXISTS roles_update ON roles;
CREATE POLICY roles_update ON roles FOR UPDATE TO authenticated
  USING (tiene_permiso('gestionar_usuarios'))
  WITH CHECK (tiene_permiso('gestionar_usuarios'));

DROP POLICY IF EXISTS roles_delete ON roles;
CREATE POLICY roles_delete ON roles FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_usuarios'));

DROP POLICY IF EXISTS rol_permisos_select ON rol_permisos;
CREATE POLICY rol_permisos_select ON rol_permisos FOR SELECT TO authenticated
  USING (es_usuario_activo());

DROP POLICY IF EXISTS rol_permisos_insert ON rol_permisos;
CREATE POLICY rol_permisos_insert ON rol_permisos FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_usuarios'));

DROP POLICY IF EXISTS rol_permisos_delete ON rol_permisos;
CREATE POLICY rol_permisos_delete ON rol_permisos FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_usuarios'));

-- ── usuarios ────────────────────────────────────────────────
-- **La tabla más delicada de todas: es la que se lee para loguearse.** Si
-- esta política queda mal, NADIE entra a la app, el admin incluido, y la
-- app no puede arreglarse sola. Ver el orden de encendido del punto 7.
--
-- La fila propia se resuelve con `auth_id = auth.uid()` directo, sin pasar
-- por una función: es la comparación que hace `AuthService._perfilPorAuthId`
-- y así no hay ninguna chance de recursión.
DROP POLICY IF EXISTS usuarios_select ON usuarios;
CREATE POLICY usuarios_select ON usuarios FOR SELECT TO authenticated
  USING (auth_id = auth.uid() OR tiene_permiso('gestionar_usuarios'));

-- El UPDATE tiene dos caminos: el admin edita cualquier perfil, y cada uno
-- puede tocar SU fila — que es lo que necesita `cambiarPassword` para borrar
-- su propio `password_hash` viejo.
DROP POLICY IF EXISTS usuarios_update ON usuarios;
CREATE POLICY usuarios_update ON usuarios FOR UPDATE TO authenticated
  USING (auth_id = auth.uid() OR tiene_permiso('gestionar_usuarios'))
  WITH CHECK (auth_id = auth.uid() OR tiene_permiso('gestionar_usuarios'));

DROP POLICY IF EXISTS usuarios_insert ON usuarios;
CREATE POLICY usuarios_insert ON usuarios FOR INSERT TO authenticated
  WITH CHECK (tiene_permiso('gestionar_usuarios'));

DROP POLICY IF EXISTS usuarios_delete ON usuarios;
CREATE POLICY usuarios_delete ON usuarios FOR DELETE TO authenticated
  USING (tiene_permiso('gestionar_usuarios'));

-- OJO con el UPDATE de la fila propia: tal como está, un usuario podría
-- cambiarse su propio `rol_id` o su `activo` por la API REST. La política no
-- puede comparar contra el valor viejo de otra columna, así que taparlo del
-- todo necesita un TRIGGER que rechace el cambio de `rol_id`, `activo` y
-- `auth_id` cuando no lo hace alguien con `gestionar_usuarios`. **Queda
-- anotado como pendiente de la Fase 2**: es una escalada de privilegios real,
-- aunque hoy nadie en la empresa sabría explotarla.


-- ════════════════════════════════════════════════════════════
-- 7. Encender RLS — COMENTADO A PROPÓSITO
-- ════════════════════════════════════════════════════════════
-- Nada de lo de arriba tiene efecto hasta que se corra esto. Se enciende
-- **tabla por tabla**, verificando la app entre una y otra, y **nunca un
-- jueves, viernes o sábado** (días de reparto).
--
-- Antes de encender la primera, el ensayo en transacción del punto 2.2 de
-- `auth_fase1_staging.md`, que prueba la política con los datos y los auth_id
-- de verdad y termina en `rollback`.
--
-- EL ORDEN IMPORTA, y no es alfabético:
--
-- GRUPO 1 — donde está la exposición y el riesgo operativo es bajo.
--   Son las tablas que la publishable key hoy regala y que ningún rol
--   necesita para trabajar si la política falla (se ven mal, no bloquean).
--     ALTER TABLE costos_semana        ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE cargas_eliminadas    ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE carga_pagos_eliminados ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE remitos_eliminados   ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE pagos_eliminados     ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE notas_pedido_eliminadas ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE notas_cd_eliminadas  ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE deposito_movimientos_eliminados ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE soportes             ENABLE ROW LEVEL SECURITY;
--
-- GRUPO 2 — los módulos laterales. Si algo sale mal afecta a un rol y a una
--   pantalla, no al circuito de plata.
--     ALTER TABLE proveedores          ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE cargas               ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE carga_pagos          ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE deposito_config      ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE deposito_movimientos ENABLE ROW LEVEL SECURITY;
--
-- GRUPO 3 — el corazón. Acá vive lo que más importa (1871 pagos, 1087
--   remitos, 108 clientes) y también lo que para el negocio. **Requiere el
--   arreglo de `cargarDatos()` deployado**: es el grupo donde una tabla
--   denegada que vuelve vacía infla los saldos.
--     ALTER TABLE vendedores           ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE clientes             ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE remitos              ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE remito_items         ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE pagos                ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE pago_medios          ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE notas_credito_debito ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE notas_pedido         ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE nota_pedido_items    ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE reparto_listas       ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE reparto_items        ENABLE ROW LEVEL SECURITY;
--
-- GRUPO 4 — LAS ÚLTIMAS, y con una sesión abierta y funcionando al lado.
--   `usuarios` es la tabla que se lee para loguearse: si su política queda
--   mal, nadie entra y la app no se puede arreglar desde la app. Conviene
--   además esperar a que la Fase 3 haya borrado `password_hash`, que es el
--   único dato sensible que queda acá.
--     ALTER TABLE permisos             ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE roles                ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE rol_permisos         ENABLE ROW LEVEL SECURITY;
--     ALTER TABLE usuarios             ENABLE ROW LEVEL SECURITY;
--
-- Para apagar una (el rollback de cada paso):
--     ALTER TABLE <tabla> DISABLE ROW LEVEL SECURITY;
--   Las políticas quedan creadas y vuelven a ignorarse. Es instantáneo y no
--   pierde nada.


-- ════════════════════════════════════════════════════════════
-- 8. El bucket de soporte: sacarle `anon`
-- ════════════════════════════════════════════════════════════
-- La Fase 1 dejó las policies del bucket `TO anon, authenticated` para no
-- romper a los que todavía entraban por el login legacy. Una vez apagado el
-- legacy (prerequisito 3), `anon` no tiene por qué seguir ahí: los adjuntos
-- son capturas con datos de clientes adentro.
--
-- Esto SÍ se puede correr apenas el legacy esté apagado y deployado: no
-- depende de ninguno de los grupos de arriba.
DROP POLICY IF EXISTS "soporte_adjuntos_insert" ON storage.objects;
CREATE POLICY "soporte_adjuntos_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'soporte-adjuntos');

DROP POLICY IF EXISTS "soporte_adjuntos_select" ON storage.objects;
CREATE POLICY "soporte_adjuntos_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'soporte-adjuntos');


-- ════════════════════════════════════════════════════════════
-- 9. Verificación (no modifica nada)
-- ════════════════════════════════════════════════════════════
-- Qué tablas tienen RLS encendido y cuántas políticas tiene cada una. Al
-- correr este archivo, `rls_activo` tiene que decir false en TODAS: las
-- políticas existen y se ignoran.
--
--   SELECT c.relname AS tabla,
--          c.relrowsecurity AS rls_activo,
--          count(p.polname) AS politicas
--   FROM pg_class c
--   JOIN pg_namespace n ON n.oid = c.relnamespace
--   LEFT JOIN pg_policy p ON p.polrelid = c.oid
--   WHERE n.nspname = 'public' AND c.relkind = 'r'
--   GROUP BY c.relname, c.relrowsecurity
--   ORDER BY c.relname;
--
-- Y que las funciones nuevas contesten false sin sesión:
--
--   SELECT public.es_usuario_activo(), public.puede_ver_saldo();
