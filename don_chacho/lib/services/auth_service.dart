// ============================================================
// SERVICIO DE AUTENTICACIÓN
// ============================================================
// Login con usuario + contraseña (SHA-256 hash)
// Sesión persistente con SharedPreferences (web: localStorage)
// ============================================================

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AuthService {
  static final _client = Supabase.instance.client;
  static const _keyUsuarioId = 'don_chacho_usuario_id';

  /// Hash SHA-256 de un password
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// Intenta login con usuario y contraseña
  /// Retorna el Usuario con su Rol y permisos cargados, o null si falla
  static Future<Usuario?> login(String usuario, String password) async {
    final hash = hashPassword(password);

    final data = await _client
        .from('usuarios')
        .select()
        .eq('usuario', usuario.trim().toLowerCase())
        .eq('password_hash', hash)
        .eq('activo', true)
        .maybeSingle();

    if (data == null) return null;

    final user = Usuario.fromMap(data);
    user.rol = await _cargarRol(user.rolId);

    // Guardar sesión
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsuarioId, user.id);

    return user;
  }

  /// Restaura sesión guardada (al abrir la app)
  static Future<Usuario?> restaurarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUsuarioId);
    if (userId == null) return null;

    final data = await _client
        .from('usuarios')
        .select()
        .eq('id', userId)
        .eq('activo', true)
        .maybeSingle();

    if (data == null) {
      await prefs.remove(_keyUsuarioId);
      return null;
    }

    final user = Usuario.fromMap(data);
    user.rol = await _cargarRol(user.rolId);
    return user;
  }

  /// Cerrar sesión
  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsuarioId);
  }

  /// Carga un Rol con sus permisos
  static Future<Rol> _cargarRol(String rolId) async {
    final rolData = await _client
        .from('roles')
        .select()
        .eq('id', rolId)
        .single();

    final permisosData = await _client
        .from('rol_permisos')
        .select('permiso_id')
        .eq('rol_id', rolId);

    final permisoIds =
        permisosData.map<String>((p) => p['permiso_id'] as String).toList();

    return Rol.fromMap(rolData, permisoIds: permisoIds);
  }

  // ═══════════════════════════════════════════
  // CRUD USUARIOS (solo admin)
  // ═══════════════════════════════════════════

  static Future<List<Usuario>> getUsuarios() async {
    final data = await _client
        .from('usuarios')
        .select()
        .order('creado_en', ascending: false);
    final usuarios =
        data.map<Usuario>((e) => Usuario.fromMap(e)).toList();

    // Cargar rol de cada usuario
    for (final u in usuarios) {
      u.rol = await _cargarRol(u.rolId);
    }
    return usuarios;
  }

  static Future<Usuario> crearUsuario(Usuario usuario) async {
    final data = await _client
        .from('usuarios')
        .insert(usuario.toMap())
        .select()
        .single();
    final u = Usuario.fromMap(data);
    u.rol = await _cargarRol(u.rolId);
    return u;
  }

  static Future<Usuario> actualizarUsuario(Usuario usuario) async {
    final data = await _client
        .from('usuarios')
        .update(usuario.toMap())
        .eq('id', usuario.id)
        .select()
        .single();
    final u = Usuario.fromMap(data);
    u.rol = await _cargarRol(u.rolId);
    return u;
  }

  static Future<void> eliminarUsuario(String usuarioId) async {
    await _client.from('usuarios').delete().eq('id', usuarioId);
  }

  // ═══════════════════════════════════════════
  // CRUD ROLES (solo admin)
  // ═══════════════════════════════════════════

  static Future<List<Rol>> getRoles() async {
    final data = await _client
        .from('roles')
        .select()
        .order('creado_en', ascending: true);
    final roles = <Rol>[];
    for (final r in data) {
      final permisosData = await _client
          .from('rol_permisos')
          .select('permiso_id')
          .eq('rol_id', r['id']);
      final permisoIds =
          permisosData.map<String>((p) => p['permiso_id'] as String).toList();
      roles.add(Rol.fromMap(r, permisoIds: permisoIds));
    }
    return roles;
  }

  static Future<Rol> crearRol(Rol rol) async {
    final data = await _client
        .from('roles')
        .insert(rol.toMap())
        .select()
        .single();

    // Insertar permisos
    for (final pid in rol.permisoIds) {
      await _client.from('rol_permisos').insert({
        'rol_id': data['id'],
        'permiso_id': pid,
      });
    }

    return Rol.fromMap(data, permisoIds: rol.permisoIds);
  }

  static Future<Rol> actualizarRol(Rol rol) async {
    final data = await _client
        .from('roles')
        .update(rol.toMap())
        .eq('id', rol.id)
        .select()
        .single();

    // Reemplazar permisos
    await _client.from('rol_permisos').delete().eq('rol_id', rol.id);
    for (final pid in rol.permisoIds) {
      await _client.from('rol_permisos').insert({
        'rol_id': rol.id,
        'permiso_id': pid,
      });
    }

    return Rol.fromMap(data, permisoIds: rol.permisoIds);
  }

  static Future<void> eliminarRol(String rolId) async {
    await _client.from('rol_permisos').delete().eq('rol_id', rolId);
    await _client.from('roles').delete().eq('id', rolId);
  }

  // ═══════════════════════════════════════════
  // PERMISOS (catálogo)
  // ═══════════════════════════════════════════

  static Future<List<Permiso>> getPermisos() async {
    final data = await _client.from('permisos').select();
    return data.map<Permiso>((e) => Permiso.fromMap(e)).toList();
  }

  // ═══════════════════════════════════════════
  // CAMBIO DE CONTRASEÑA
  // ═══════════════════════════════════════════

  static Future<bool> cambiarPassword(
      String usuarioId, String passwordActual, String passwordNueva) async {
    final hashActual = hashPassword(passwordActual);
    final data = await _client
        .from('usuarios')
        .select('id')
        .eq('id', usuarioId)
        .eq('password_hash', hashActual)
        .maybeSingle();

    if (data == null) return false;

    await _client.from('usuarios').update({
      'password_hash': hashPassword(passwordNueva),
    }).eq('id', usuarioId);

    return true;
  }
}
