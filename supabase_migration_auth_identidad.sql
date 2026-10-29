-- ============================================================
-- MIGRACIÓN: identidad real de Supabase Auth para cada usuario (Fase 1)
-- ============================================================
-- Hoy la base no sabe quién pregunta. La app se conecta siempre con la
-- publishable key, el login es propio (`usuarios.password_hash`, SHA-256 sin
-- sal) y la sesión es el id del usuario guardado en el navegador. Para
-- Postgres todas las consultas son el mismo rol `anon` sin nombre y sin
-- dueño, así que no hay forma de escribir una política de RLS: `auth.uid()`
-- devuelve NULL siempre.
--
-- Esta migración le da a cada usuario una identidad de `auth.users` y deja
-- las dos funciones que las políticas de la FASE SIGUIENTE van a usar para
-- traducir esa identidad a "qué puede hacer": `es_admin()` y
-- `tiene_permiso(text)`.
--
-- ESTA MIGRACIÓN NO HABILITA RLS EN NINGUNA TABLA. A propósito: encender RLS
-- y crear las identidades el mismo día dejaría al negocio sin red. Primero
-- todos entran con su cuenta nueva (y se verifica que entran), después se
-- escriben las políticas. Ver `auth_fase1_diseno.md` y `auth_fase1_runbook.md`.
--
-- ORDEN DE EJECUCIÓN (el runbook lo explica paso por paso):
--   PASO 1  → este archivo, de `-- ── 1.` a `-- ── 4.`  (antes de crear las cuentas)
--   PASO 2  → crear las 6 cuentas a mano en el dashboard
--   PASO 3  → el bloque `-- ── 5.` de este mismo archivo (vincula perfil ↔ cuenta)
--   PASO 4  → deployar la app
--
-- Todo es idempotente: se puede volver a correr sin romper nada.
-- ============================================================


-- ── 1. La columna que une el perfil con la identidad ────────
-- NULLABLE a propósito: entre correr esto y crear las 6 cuentas hay una
-- ventana en la que ningún perfil tiene identidad todavía, y la app tiene
-- que seguir andando (login legacy) durante esa ventana.
--
-- ON DELETE SET NULL y no CASCADE: si alguien borra la cuenta de Auth por
-- error, el perfil tiene que quedar — con su rol, su nombre y su historia —
-- y volverse a vincular. Con CASCADE se perdería el usuario entero.
ALTER TABLE usuarios
  ADD COLUMN IF NOT EXISTS auth_id UUID
  REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN usuarios.auth_id IS
  'Identidad de Supabase Auth de este usuario. NULL = todavía no tiene cuenta '
  '(login legacy por password_hash). Lo resuelven es_admin() y tiene_permiso().';


-- ── 2. Índice ───────────────────────────────────────────────
-- UNIQUE y no un índice común: dos perfiles con la misma identidad harían
-- que `es_admin()` dependa de cuál fila devuelve Postgres primero, que es
-- exactamente el tipo de permiso que no se puede dejar al azar. En Postgres
-- un índice UNIQUE deja pasar todos los NULL que haga falta, así que los
-- perfiles sin cuenta todavía no se estorban entre sí.
--
-- Además es el índice que necesitan las funciones de abajo: las va a llamar
-- cada política de cada tabla, así que la búsqueda por auth_id tiene que ser
-- un index scan y no un seq scan.
CREATE UNIQUE INDEX IF NOT EXISTS idx_usuarios_auth_id
  ON usuarios (auth_id);


-- ── 3. es_admin() ───────────────────────────────────────────
-- ¿El que está preguntando es el dueño?
--
-- SECURITY DEFINER no es un lujo: en la fase siguiente `usuarios` y `roles`
-- también van a tener RLS, y una política de `pagos` que llame a esta
-- función tendría que leer `usuarios`, lo que dispararía la política de
-- `usuarios`, que vuelve a preguntar quién es... recursión infinita. Es el
-- error clásico de RLS en Supabase. Con SECURITY DEFINER la función corre
-- como su dueño y saltea las políticas de las tablas que lee.
--
-- STABLE para que Postgres la llame UNA vez por consulta y no una vez por
-- fila: con 1871 pagos la diferencia es entre una consulta y 1871.
--
-- SET search_path es la contracara obligatoria de SECURITY DEFINER: sin él,
-- quien pueda crear un esquema puede plantar una tabla `usuarios` propia y
-- hacer que la función conteste lo que le convenga.
--
-- `u.activo` va adentro: dar de baja a alguien en Gestión de Usuarios tiene
-- que cerrarle la puerta en la base, no solo esconderle los botones.
CREATE OR REPLACE FUNCTION public.es_admin()
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
      AND r.es_admin
  );
$$;

COMMENT ON FUNCTION public.es_admin() IS
  'true si quien hace la consulta es un usuario activo con rol es_admin. '
  'Sin sesión (auth.uid() NULL) devuelve false. Para las políticas de RLS.';


-- ── 4. tiene_permiso(text) ──────────────────────────────────
-- ¿El que está preguntando tiene este permiso del catálogo?
--
-- El catálogo es el que ya existe en `permisos` (14 filas): esto no inventa
-- permisos nuevos, solo lee los que la app ya usa para armar las pestañas.
--
-- `r.es_admin OR ...`: misma regla que `Rol.tienePermiso` en Dart, donde el
-- admin da true a cualquier permiso sin tener la fila en `rol_permisos`. Si
-- la base y la app no coincidieran en esto, el dueño vería un botón que la
-- base le rechaza.
--
-- No valida que el permiso exista en el catálogo: un nombre mal escrito
-- devuelve false, que es el lado seguro del error.
CREATE OR REPLACE FUNCTION public.tiene_permiso(p_permiso TEXT)
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
          SELECT 1
          FROM rol_permisos rp
          WHERE rp.rol_id = r.id
            AND rp.permiso_id = p_permiso
        )
      )
  );
$$;

COMMENT ON FUNCTION public.tiene_permiso(TEXT) IS
  'true si quien hace la consulta es un usuario activo cuyo rol tiene ese '
  'permiso del catálogo `permisos` (el admin tiene todos). Sin sesión, false.';

-- Las dos las van a llamar las políticas, y una política corre con el rol de
-- quien consulta. Se otorga explícito en vez de confiar en el EXECUTE que
-- Postgres le da a PUBLIC por default: si alguna vez se revoca ese default
-- (buena práctica), las políticas empezarían a dar "permission denied" en
-- vez de false, y eso con RLS encendido es el negocio parado.
--
-- `anon` incluido a propósito: sin sesión las dos devuelven false, que es
-- justo lo que la fase siguiente necesita que conteste la publishable key
-- sola. Negarle el EXECUTE no la haría más segura, la haría romper.
GRANT EXECUTE ON FUNCTION public.es_admin() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tiene_permiso(TEXT) TO anon, authenticated;


-- ── 5. PASO 3 — vincular perfil ↔ cuenta ────────────────────
-- Se corre DESPUÉS de crear las 6 cuentas en el dashboard (ver el runbook).
-- Corrido antes, no hace nada: no hay cuentas que matchear.
--
-- El vínculo se resuelve solo por el mail sintético: la cuenta de Auth de
-- `rociolopez` es `rociolopez@donchacho.local`. Así nadie tiene que copiar
-- UUIDs a mano, que es donde se cometen los errores que después cuesta
-- encontrar.
--
-- `WHERE u.auth_id IS NULL` hace que sea seguro re-correrlo: no repisa un
-- vínculo que ya está hecho.
UPDATE usuarios u
SET auth_id = a.id
FROM auth.users a
WHERE a.email = lower(u.usuario) || '@donchacho.local'
  AND u.auth_id IS NULL;


-- ── 6. Adjuntos de soporte: el bucket también cambia de rol ─
-- Las policies del bucket `soporte-adjuntos` (v18.36) están escritas
-- `TO anon`, porque hasta hoy la app se conectaba siempre como anon. Con
-- sesión de Supabase Auth las consultas pasan a llegar como `authenticated`,
-- y esas policies dejan de matchear: adjuntar la foto de un reclamo y firmar
-- el link para verla empezarían a fallar el día del deploy.
--
-- `storage.objects` tiene RLS SIEMPRE encendido (es de Supabase, no del
-- negocio), así que esto no contradice el "no se habilita RLS en esta fase":
-- es mantener funcionando lo que ya estaba.
--
-- Se dejan los dos roles: `anon` para que la app siga andando mientras
-- queden usuarios entrando por el login legacy, `authenticated` para los que
-- ya entran con su cuenta.
DROP POLICY IF EXISTS "soporte_adjuntos_insert" ON storage.objects;
CREATE POLICY "soporte_adjuntos_insert" ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'soporte-adjuntos');

DROP POLICY IF EXISTS "soporte_adjuntos_select" ON storage.objects;
CREATE POLICY "soporte_adjuntos_select" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'soporte-adjuntos');


-- ── 7. Verificación (leer el resultado, no modifica nada) ───
-- Qué perfil quedó con cuenta y qué perfil no. Al terminar el PASO 3 las 6
-- filas tienen que decir 'vinculado'. Es el check del runbook.
--
--   SELECT u.usuario,
--          u.nombre_completo,
--          r.nombre AS rol,
--          u.activo,
--          CASE WHEN u.auth_id IS NULL THEN 'SIN CUENTA' ELSE 'vinculado' END
--            AS identidad,
--          a.email
--   FROM usuarios u
--   JOIN roles r ON r.id = u.rol_id
--   LEFT JOIN auth.users a ON a.id = u.auth_id
--   ORDER BY u.usuario;
--
-- Y que las funciones existan y contesten false sin sesión (en el SQL Editor
-- no hay `auth.uid()`, así que false es la respuesta correcta):
--
--   SELECT public.es_admin(), public.tiene_permiso('crear_pago');
