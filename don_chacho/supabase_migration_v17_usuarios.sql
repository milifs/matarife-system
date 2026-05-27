-- ════════════════════════════════════════════════════════════
-- MIGRATION v17: Sistema de Usuarios, Roles, Permisos y
-- Confirmación de Remitos
-- ════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════
-- 1. CATÁLOGO DE PERMISOS
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS permisos (
    id TEXT PRIMARY KEY,
    nombre TEXT NOT NULL,
    descripcion TEXT
);

INSERT INTO permisos (id, nombre, descripcion) VALUES
    ('crear_remito', 'Crear remitos', 'Cargar nuevos remitos manualmente'),
    ('usar_ocr', 'Usar OCR', 'Cargar remitos con foto (OCR)'),
    ('confirmar_remito', 'Confirmar remitos', 'Aprobar/rechazar remitos pendientes'),
    ('editar_remito', 'Editar remitos', 'Modificar remitos existentes'),
    ('eliminar_remito', 'Eliminar remitos', 'Borrar remitos del sistema'),
    ('crear_pago', 'Crear pagos', 'Registrar pagos'),
    ('editar_pago', 'Editar pagos', 'Modificar/eliminar pagos'),
    ('gestionar_clientes', 'Gestionar clientes', 'ABM de clientes'),
    ('gestionar_vendedores', 'Gestionar vendedores', 'ABM de vendedores'),
    ('gestionar_costos', 'Gestionar costos', 'Ver y editar costos por semana'),
    ('ver_consultas', 'Ver consultas', 'Acceso a consultas, saldos, ganancias'),
    ('gestionar_usuarios', 'Gestionar usuarios', 'Crear/editar usuarios y roles')
ON CONFLICT (id) DO NOTHING;

-- ═══════════════════════════════════════════
-- 2. ROLES
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre TEXT NOT NULL UNIQUE,
    es_admin BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO roles (id, nombre, es_admin) VALUES
    ('00000000-0000-0000-0000-000000000001', 'Administrador', TRUE),
    ('00000000-0000-0000-0000-000000000002', 'Secretaria', FALSE)
ON CONFLICT (nombre) DO NOTHING;

-- ═══════════════════════════════════════════
-- 3. PERMISOS POR ROL
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS rol_permisos (
    rol_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permiso_id TEXT NOT NULL REFERENCES permisos(id) ON DELETE CASCADE,
    PRIMARY KEY (rol_id, permiso_id)
);

-- Asignar TODOS los permisos al Administrador
INSERT INTO rol_permisos (rol_id, permiso_id)
SELECT '00000000-0000-0000-0000-000000000001', id FROM permisos
ON CONFLICT DO NOTHING;

-- Secretaria solo puede crear remitos
INSERT INTO rol_permisos (rol_id, permiso_id) VALUES
    ('00000000-0000-0000-0000-000000000002', 'crear_remito')
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════
-- 4. USUARIOS
-- ═══════════════════════════════════════════
CREATE TABLE IF NOT EXISTS usuarios (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    usuario TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    rol_id UUID NOT NULL REFERENCES roles(id),
    nombre_completo TEXT NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Usuario Administrador inicial
-- Usuario: admin / Password: admin123 (cambialo después desde la app)
-- El hash es SHA-256 de 'admin123'
INSERT INTO usuarios (id, usuario, password_hash, rol_id, nombre_completo)
VALUES (
    '00000000-0000-0000-0000-000000000099',
    'admin',
    '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9',
    '00000000-0000-0000-0000-000000000001',
    'Administrador'
) ON CONFLICT (usuario) DO NOTHING;

-- ═══════════════════════════════════════════
-- 5. CONFIRMACIÓN DE REMITOS
-- ═══════════════════════════════════════════
ALTER TABLE remitos
    ADD COLUMN IF NOT EXISTS estado TEXT NOT NULL DEFAULT 'confirmado'
        CHECK (estado IN ('pendiente', 'confirmado', 'rechazado')),
    ADD COLUMN IF NOT EXISTS creado_por UUID REFERENCES usuarios(id),
    ADD COLUMN IF NOT EXISTS confirmado_por UUID REFERENCES usuarios(id),
    ADD COLUMN IF NOT EXISTS confirmado_en TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS motivo_rechazo TEXT;

-- Marcar todos los remitos existentes como 'confirmado'
UPDATE remitos SET estado = 'confirmado' WHERE estado IS NULL;

-- ═══════════════════════════════════════════
-- 6. ÍNDICES
-- ═══════════════════════════════════════════
CREATE INDEX IF NOT EXISTS idx_remitos_estado ON remitos(estado);
CREATE INDEX IF NOT EXISTS idx_usuarios_usuario ON usuarios(usuario);
CREATE INDEX IF NOT EXISTS idx_rol_permisos_rol ON rol_permisos(rol_id);

-- ═══════════════════════════════════════════
-- 7. FIX COLUMNA VIEJA costo_por_kg (por las dudas)
-- ═══════════════════════════════════════════
ALTER TABLE costos_semana
    ALTER COLUMN costo_por_kg DROP NOT NULL;
ALTER TABLE costos_semana
    ALTER COLUMN costo_por_kg SET DEFAULT 0;
