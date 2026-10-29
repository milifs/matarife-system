-- ============================================================
-- MIGRACIÓN: el ticket de soporte sabe de QUIÉN es (Fase 2) — NO CORRIDA
-- ============================================================
-- Prerequisito de la política `soportes_select` de
-- `supabase_migration_rls_politicas.sql`, que implementa "cada uno ve sus
-- propios tickets y el admin ve todos".
--
-- POR QUÉ NO ALCANZA CON LO QUE HAY
--
-- Hoy el dueño del ticket es `soportes.reportado_por`, que es TEXT con el
-- nombre completo: `soporte_form_screen.dart` filtra con
-- `getTicketsSoporte(reportadoPor: usuario.nombreCompleto)`.
--
-- Eso FUNCIONA hoy — los seis nombres completos son distintos — pero no
-- aguanta una política de RLS, por tres razones:
--
--   1. `nombre_completo` no tiene restricción de unicidad y nada impide que
--      se repita: son dos personas escribiendo un nombre en un formulario. El
--      día que se repita, cada una ve los tickets de la otra.
--   2. Renombrar a alguien en Gestión de Usuarios le borra su historia: sus
--      tickets anteriores dejan de ser suyos, sin aviso.
--   3. Depende de tildes y mayúsculas. "soledad Alcalá" está guardado así,
--      con minúscula inicial y con tilde; cualquier corrección cosmética de
--      ese nombre rompe el match.
--
-- Un permiso no se puede apoyar en un campo de texto que la gente edita.
-- ============================================================


-- ── 1. La columna ───────────────────────────────────────────
-- Apunta a `usuarios.id` (el perfil) y no a `auth.users.id` (la identidad):
-- el ticket es de la persona dentro del negocio, y si alguna vez hay que
-- recrear su cuenta de Auth, sus reclamos tienen que seguir siendo suyos.
--
-- ON DELETE SET NULL: borrar un usuario no borra sus reclamos. Un ticket sin
-- dueño lo sigue viendo el admin (ver la política), que es lo que corresponde
-- — es el que tiene que resolverlo.
ALTER TABLE soportes
  ADD COLUMN IF NOT EXISTS reportado_por_id UUID
  REFERENCES usuarios(id) ON DELETE SET NULL;

COMMENT ON COLUMN soportes.reportado_por_id IS
  'Perfil que abrió el ticket. Es el campo que usa la política de RLS. La '
  'columna de texto reportado_por queda para mostrar y para los tickets '
  'viejos que no se pudieron vincular.';

-- La política hace `reportado_por_id IN (select id from usuarios where
-- auth_id = auth.uid())` en cada fila leída, así que esto no es opcional.
CREATE INDEX IF NOT EXISTS idx_soportes_reportado_por_id
  ON soportes (reportado_por_id);


-- ── 2. Backfill de los tickets que ya existen ───────────────
-- Se vincula por nombre completo, que es el único puente que hay, pero
-- **solo cuando el nombre identifica a UNA sola persona**. Si un nombre
-- estuviera repetido en `usuarios`, adivinar sería peor que dejarlo en NULL:
-- le daría los tickets de alguien a otra persona, que es exactamente lo que
-- esta migración viene a impedir.
--
-- Se compara con `lower(btrim(...))` para que una tilde de más o un espacio
-- al final no dejen afuera una fila; lo que no se toca es el criterio de
-- ambigüedad.
UPDATE soportes s
SET reportado_por_id = m.id
FROM (
  SELECT lower(btrim(nombre_completo)) AS nombre,
         min(id::text)::uuid           AS id,
         count(*)                      AS cuantos
  FROM usuarios
  WHERE nombre_completo IS NOT NULL
    AND btrim(nombre_completo) <> ''
  GROUP BY 1
) m
WHERE m.cuantos = 1
  AND s.reportado_por_id IS NULL
  AND s.reportado_por IS NOT NULL
  AND lower(btrim(s.reportado_por)) = m.nombre;


-- ── 3. Verificación (no modifica nada) ──────────────────────
-- Qué quedó vinculado y qué no. Lo que quede en NULL **no se pierde**: lo
-- sigue viendo el admin en la bandeja, solo que su autor no lo ve en la lista
-- de "mis últimos reclamos".
--
--   SELECT CASE WHEN reportado_por_id IS NULL
--               THEN 'sin vincular' ELSE 'vinculado' END AS estado,
--          count(*)
--   FROM soportes
--   GROUP BY 1;
--
-- Y, si quedó alguno sin vincular, con qué nombre está guardado — para poder
-- decidir a mano si vale la pena asignarlo:
--
--   SELECT numero, reportado_por, creado_en
--   FROM soportes
--   WHERE reportado_por_id IS NULL
--   ORDER BY creado_en;
--
-- Para asignar uno a mano:
--   UPDATE soportes SET reportado_por_id =
--     (SELECT id FROM usuarios WHERE usuario = 'rociolopez')
--   WHERE numero = 7;
--
-- NO se pone la columna NOT NULL: los tickets viejos sin vincular tienen que
-- poder quedarse así. La que garantiza que los NUEVOS vengan con dueño es la
-- política de INSERT (`soportes_insert`), que exige que el `reportado_por_id`
-- sea el del que escribe.
