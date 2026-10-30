-- ============================================================
-- MIGRACIÓN: nadie se cambia su propio rol (Fase 2) — NO CORRIDA
-- ============================================================
-- Tapa el agujero que quedó anotado al pie de la sección 6 de
-- `supabase_migration_rls_politicas.sql`.
--
-- EL PROBLEMA
--
-- La política `usuarios_update` tiene que dejar que cada uno toque SU fila:
-- `AuthService.cambiarPassword` borra su propio `password_hash` viejo cuando
-- la contraseña pasa a estar en Supabase Auth (`auth_service.dart:401`), y
-- eso lo hace el usuario con su propia sesión, no un admin.
--
-- Pero una política de RLS **no puede comparar contra el valor anterior de
-- otra columna**: `WITH CHECK` ve la fila nueva, `USING` ve la vieja, y no
-- hay forma de escribir "esta columna no cambió". Así que la misma política
-- que habilita el cambio de contraseña habilita, por la API REST, un:
--
--     PATCH /rest/v1/usuarios?id=eq.<el mío>
--     { "rol_id": "<el del admin>" }
--
-- Es una escalada de privilegios real. Hoy nadie en la empresa la sabría
-- explotar, pero la publishable key viaja en el bundle y el que la encuentre
-- no necesita saber nada más: alcanza con tener una sesión propia.
--
-- LA SOLUCIÓN, Y POR QUÉ ES UN TRIGGER
--
-- Un trigger `BEFORE UPDATE` sí ve `OLD` y `NEW` a la vez. Rechaza el cambio
-- de las cuatro columnas que definen quién sos, y deja pasar todo lo demás.
--
-- **Se puede correr antes de encender RLS y conviene hacerlo**, pero no
-- protege nada hasta entonces: sin RLS, cualquiera con la publishable key y
-- sin sesión edita la tabla entera, y ahí `auth.uid()` es NULL y el trigger
-- se hace a un lado (ver abajo por qué tiene que hacerse a un lado). Es
-- **prerequisito de encender RLS en `usuarios`**, que es el grupo 4 del
-- punto 7 de la migración de políticas.
-- ============================================================


-- ── 1. La función del trigger ───────────────────────────────
-- Tres puertas de salida, en este orden, y cada una tiene su razón:
--
--   1. `auth.uid() IS NULL` → **pasa.** Es el dashboard, el SQL editor y la
--      service key. Si esto no estuviera, el PASO 3 del
--      `auth_fase1_runbook.md` quedaría bloqueado: ese UPDATE es justamente
--      el que escribe `auth_id` en las seis filas, y lo corre Mili a mano.
--      Un trigger que impida arreglar la tabla desde el dashboard es peor
--      que el agujero que tapa.
--   2. **No es su fila** → pasa, y de eso se ocupa la política: un no-admin
--      no llega ni a intentarlo, porque `usuarios_update` le exige
--      `auth_id = auth.uid()` sobre la fila vieja.
--   3. **Tiene `gestionar_usuarios`** → pasa. Esa persona ya puede cambiarle
--      el rol a cualquiera, la suya incluida, desde Gestión de Usuarios:
--      bloquearle su propia fila no agregaría ninguna seguridad y le rompería
--      una pantalla que hoy funciona.
--
-- No es SECURITY DEFINER a propósito. Lo único que consulta es
-- `tiene_permiso()`, que ya es `security definer`, así que el trigger no
-- necesita privilegios propios — y un trigger con privilegios de más sobre la
-- tabla de usuarios es exactamente lo que no se quiere.
CREATE OR REPLACE FUNCTION public.usuarios_sin_autoascenso()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF OLD.auth_id IS DISTINCT FROM auth.uid() THEN
    RETURN NEW;
  END IF;

  IF tiene_permiso('gestionar_usuarios') THEN
    RETURN NEW;
  END IF;

  -- Desde acá: alguien editando su propia fila, sin permiso de usuarios.

  IF NEW.rol_id IS DISTINCT FROM OLD.rol_id THEN
    RAISE EXCEPTION 'No se puede cambiar el rol de la propia cuenta'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.activo IS DISTINCT FROM OLD.activo THEN
    RAISE EXCEPTION 'No se puede dar de baja ni reactivar la propia cuenta'
      USING ERRCODE = '42501';
  END IF;

  -- `auth_id` es el vínculo con la identidad de Auth. Cambiarlo es apropiarse
  -- de la cuenta de otro o soltar la propia; la política ya lo frena, esto es
  -- el cinturón además del airbag.
  IF NEW.auth_id IS DISTINCT FROM OLD.auth_id THEN
    RAISE EXCEPTION 'No se puede cambiar la identidad de la propia cuenta'
      USING ERRCODE = '42501';
  END IF;

  -- `usuario` es con lo que se arma el mail sintético del login
  -- (`<usuario>@donchacho.local`). La app no ofrece cambiarlo en ninguna
  -- pantalla, y cambiarlo por la API dejaría el perfil apuntando a un mail
  -- que no es el de su cuenta de Auth: nadie gana nada y se puede perder el
  -- acceso.
  IF NEW.usuario IS DISTINCT FROM OLD.usuario THEN
    RAISE EXCEPTION 'No se puede cambiar el nombre de usuario de la propia cuenta'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.usuarios_sin_autoascenso() IS
  'Rechaza que un usuario se cambie su propio rol_id, activo, auth_id o '
  'usuario. Existe porque una política de RLS no puede comparar contra el '
  'valor anterior de otra columna, y usuarios_update tiene que dejar pasar '
  'el UPDATE de la fila propia para que cambiarPassword borre su hash viejo.';


-- ── 2. El trigger ───────────────────────────────────────────
-- `BEFORE UPDATE` y no `AFTER`: lo que se quiere es que el UPDATE **no
-- ocurra**, no deshacerlo después.
--
-- Los triggers corren esté RLS encendido o apagado, así que esto vale para
-- las dos etapas (lo que cambia es si hay por dónde atacar).
DROP TRIGGER IF EXISTS trg_usuarios_sin_autoascenso ON usuarios;
CREATE TRIGGER trg_usuarios_sin_autoascenso
  BEFORE UPDATE ON usuarios
  FOR EACH ROW
  EXECUTE FUNCTION public.usuarios_sin_autoascenso();


-- ── 3. Verificación (se corre sola, no deja nada) ───────────
-- Todo esto va dentro de una transacción que termina en `rollback`, igual que
-- el ensayo del punto 2.2 de `auth_fase1_staging.md`. **No modifica nada.**
--
-- Reemplazar <AUTH_ID> por el `auth_id` de un usuario SIN
-- `gestionar_usuarios` (por ejemplo el de una de las chicas) y <ROL_ADMIN>
-- por el id del rol de admin:
--
--   begin;
--
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"<AUTH_ID>","role":"authenticated"}';
--
--   -- 1. Cambiarse la contraseña SÍ tiene que andar (es el caso que la
--   --    política existe para habilitar):
--   update usuarios set password_hash = ''
--    where auth_id = '<AUTH_ID>';          -- esperado: UPDATE 1
--
--   -- 2. Cambiarse el rol NO:
--   update usuarios set rol_id = '<ROL_ADMIN>'
--    where auth_id = '<AUTH_ID>';          -- esperado: ERROR 42501
--
--   -- 3. Darse de baja tampoco:
--   update usuarios set activo = false
--    where auth_id = '<AUTH_ID>';          -- esperado: ERROR 42501
--
--   rollback;
--
-- Y, ya fuera de la sesión simulada, que el dashboard siga pudiendo:
--
--   begin;
--   update usuarios set activo = activo;   -- esperado: UPDATE 6, sin error
--   rollback;
--
-- Ojo con el orden: cada `update` que da ERROR aborta la transacción, así que
-- los tres casos van en bloques `begin; … rollback;` separados, o con un
-- `savepoint` antes de cada uno.
--
-- Para ver que quedó instalado:
--
--   SELECT tgname, tgenabled
--   FROM pg_trigger
--   WHERE tgrelid = 'usuarios'::regclass AND NOT tgisinternal;
