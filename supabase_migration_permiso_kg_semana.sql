-- v19.17 — Permiso `ver_kg_semana`: las dos tarjetas de kg del dashboard
--
-- Pedido de Joaquín: que la secretaria pueda ver "Kg novillo semana" y
-- "Kg cerdo semana", y NADA MÁS de la pantalla de Inicio — ni el saldo a
-- cobrar, ni los costos, ni las ganancias, ni la deuda de los vendedores.
--
-- Desde v19.14 el dashboard entero pide `es_admin`, así que hoy la secretaria
-- ve el Inicio sin plata. Este permiso abre una versión recortada de esa
-- pantalla: el selector de semana y las dos tarjetas de kg.
--
-- **Por qué un permiso y no el rol**: el gate de v19.14 es por rol (`esAdmin`)
-- porque lo que tapa es la plata del negocio de conjunto, y para eso un
-- permiso nuevo habría que acordarse de no dárselo a nadie. Acá es al revés:
-- es un recorte que se le da a alguien a propósito, y los roles son
-- configurables desde Gestión de Usuarios. El catálogo de permisos sale de
-- esta tabla, así que con este INSERT el checkbox aparece solo.
--
-- **A quién le toca**: al rol Secretaria, que es el de Rocío López (y también
-- el de Soledad Alcalá — los permisos son del rol, no del usuario; decisión
-- tomada sabiendo eso). El rol Encargado de Depósito, que es el de Rocío
-- Cejas, NO lo recibe: sigue viendo el Inicio sin plata.

-- ═══════════════════════════════════════════
-- 1. PERMISO NUEVO
-- ═══════════════════════════════════════════
INSERT INTO permisos (id, nombre, descripcion) VALUES
  ('ver_kg_semana', 'Ver kg de la semana',
   'Ver en Inicio los kg de novillo y de cerdo vendidos en la semana')
ON CONFLICT (id) DO NOTHING;

-- Todos los roles admin lo reciben automáticamente. Hoy no cambia nada —el
-- admin ve el dashboard entero por `es_admin`— pero deja el catálogo
-- coherente: no hay permiso que el administrador no tenga.
INSERT INTO rol_permisos (rol_id, permiso_id)
SELECT r.id, 'ver_kg_semana' FROM roles r WHERE r.es_admin = TRUE
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════
-- 2. AL ROL SECRETARIA
-- ═══════════════════════════════════════════
-- Por nombre y no por el id fijo (`00000000-…-0002`) para que la migración
-- también sirva en una instalación donde el rol se haya creado a mano.
INSERT INTO rol_permisos (rol_id, permiso_id)
SELECT r.id, 'ver_kg_semana' FROM roles r WHERE r.nombre = 'Secretaria'
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════
-- 3. VERIFICACIÓN
-- ═══════════════════════════════════════════
-- Tiene que devolver el Administrador y la Secretaria, y NO al Encargado de
-- Depósito ni al Cobrador.
--
--   SELECT r.nombre, r.es_admin
--   FROM rol_permisos rp JOIN roles r ON r.id = rp.rol_id
--   WHERE rp.permiso_id = 'ver_kg_semana'
--   ORDER BY r.nombre;
