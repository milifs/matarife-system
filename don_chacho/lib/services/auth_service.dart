// ============================================================
// SERVICIO DE AUTENTICACIÓN
// ============================================================
// La identidad la pone Supabase Auth; el rol y los permisos siguen viviendo
// en la tabla `usuarios` (perfil).
//
// Joaco y las chicas escriben "rociolopez", no un mail: el usuario se traduce
// a un MAIL SINTÉTICO (`rociolopez@donchacho.local`) y con eso se hace
// `signInWithPassword`. El dominio `.local` no existe en internet a
// propósito — no son casillas, son nombres de cuenta.
//
// La sesión es la de Supabase (la persiste el SDK y se refresca sola). Ya no
// se guarda el id del usuario en SharedPreferences, salvo por el login legacy
// de abajo.
//
// LOGIN LEGACY (transitorio): hasta que los 6 usuarios tengan su cuenta de
// Auth creada y verificada, el login viejo por `password_hash` (SHA-256 sin
// sal) sigue disponible como red. Ver [permitirLoginLegacy].
// ============================================================

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Qué pasó al intentar cambiar la contraseña. Un bool no alcanza: "la actual
/// está mal" y "tu cuenta todavía no existe" se arreglan de formas distintas
/// y el usuario tiene que leer cuál de las dos le pasó.
enum ResultadoCambioPassword {
  ok,

  /// La contraseña actual no es la que tiene la cuenta.
  actualIncorrecta,

  /// El usuario entró por el login legacy: no tiene identidad de Supabase
  /// Auth todavía, así que no hay contraseña de Auth que cambiar.
  sinCuentaDeAuth,

  /// La nueva no cumple el mínimo que pide Supabase (o Auth la rechazó).
  nuevaRechazada,
}

class AuthService {
  static final _client = Supabase.instance.client;
  static const _keyUsuarioId = 'don_chacho_usuario_id';

  /// Dominio de los mails sintéticos. No es una casilla real y no tiene que
  /// serlo: nadie recibe mail acá, es la forma que tiene Supabase Auth de
  /// nombrar una cuenta.
  static const dominioSintetico = 'donchacho.local';

  /// Mínimo de caracteres de una contraseña nueva. Supabase pide 6 por
  /// default; acá se pide 8 porque el hash viejo era SHA-256 sin sal y la
  /// lección de esa historia es que las contraseñas cortas no aguantan nada.
  static const minPassword = 8;

  /// Mientras valga `true`, un usuario sin cuenta de Auth todavía puede
  /// entrar con su contraseña vieja.
  ///
  /// **Hay que apagarlo antes de encender RLS.** Un login legacy no abre
  /// sesión de Supabase, así que `auth.uid()` queda NULL: con RLS encendido
  /// ese usuario vería **todas las tablas vacías** (no un error), y la app le
  /// mostraría saldos inflados en vez de avisarle que no puede trabajar.
  ///
  /// Se apaga en el deploy siguiente al runbook, cuando los 6 confirmaron que
  /// entran con su cuenta nueva.
  static const permitirLoginLegacy = true;

  /// El mail sintético de un nombre de usuario.
  static String mailDe(String usuario) =>
      '${usuario.trim().toLowerCase()}@$dominioSintetico';

  /// Los cambios de sesión de Supabase. `main.dart` los escucha para que un
  /// token revocado o vencido saque al usuario a la pantalla de login en vez
  /// de dejarlo adentro con una app que ya no puede leer nada.
  static Stream<AuthState> get cambiosDeSesion => _client.auth.onAuthStateChange;

  /// Hash SHA-256 de un password. **Solo para el login legacy**: las
  /// contraseñas nuevas las guarda Supabase Auth con bcrypt.
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// Intenta login con usuario y contraseña.
  /// Retorna el Usuario con su Rol y permisos cargados, o null si falla.
  static Future<Usuario?> login(String usuario, String password) async {
    final nombre = usuario.trim().toLowerCase();

    try {
      final res = await _client.auth.signInWithPassword(
        email: mailDe(nombre),
        password: password,
      );

      if (res.session != null) {
        final perfil = await _perfilPorAuthId(res.session!.user.id);
        if (perfil != null) return perfil;

        // Hay identidad pero no hay perfil activo: o nadie la vinculó, o el
        // admin dio de baja al usuario. La sesión no se deja abierta — sin
        // perfil no hay rol, y una sesión sin rol es una sesión que no sabe
        // decir qué puede hacer.
        await cerrarSesion();
        return null;
      }
    } on AuthException {
      // Cuenta inexistente o contraseña incorrecta. Puede ser un usuario al
      // que todavía no le crearon la cuenta, así que se prueba el legacy.
    }

    if (!permitirLoginLegacy) return null;
    return _loginLegacy(nombre, password);
  }

  /// Login viejo por `password_hash`. Transitorio: ver [permitirLoginLegacy].
  ///
  /// No abre sesión de Supabase, así que `auth.uid()` queda NULL para este
  /// usuario y la sesión se sigue guardando en SharedPreferences.
  static Future<Usuario?> _loginLegacy(String usuario, String password) async {
    final hash = hashPassword(password);

    final data = await _client
        .from('usuarios')
        .select()
        .eq('usuario', usuario)
        .eq('password_hash', hash)
        .eq('activo', true)
        .maybeSingle();

    if (data == null) return null;

    final user = Usuario.fromMap(data);
    user.rol = await _cargarRol(user.rolId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsuarioId, user.id);

    return user;
  }

  /// Restaura sesión guardada (al abrir la app).
  ///
  /// Primero la de Supabase, que es la que vale. El SDK ya la recuperó y la
  /// refrescó durante `Supabase.initialize`, así que acá solo hay que buscar
  /// el perfil que le corresponde.
  static Future<Usuario?> restaurarSesion() async {
    final sesion = _client.auth.currentSession;
    if (sesion != null) {
      final perfil = await _perfilPorAuthId(sesion.user.id);
      if (perfil != null) return perfil;
      await cerrarSesion();
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_keyUsuarioId);
    if (userId == null) return null;

    // Sin sesión de Supabase y sin legacy habilitado, la sesión guardada no
    // vale nada: se limpia para que no quede dando vueltas.
    if (!permitirLoginLegacy) {
      await prefs.remove(_keyUsuarioId);
      return null;
    }

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

  /// Cerrar sesión: la de Supabase y la guardada del legacy.
  static Future<void> cerrarSesion() async {
    try {
      await _client.auth.signOut();
    } on AuthException {
      // Sin sesión abierta (login legacy, o token ya vencido del lado del
      // servidor). No hay nada que cerrar y no es un error para el usuario.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsuarioId);
  }

  /// El perfil (rol + permisos) que corresponde a una identidad de Auth.
  static Future<Usuario?> _perfilPorAuthId(String authId) async {
    final data = await _client
        .from('usuarios')
        .select()
        .eq('auth_id', authId)
        .eq('activo', true)
        .maybeSingle();

    if (data == null) return null;

    final user = Usuario.fromMap(data);
    user.rol = await _cargarRol(user.rolId);
    return user;
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

  /// Crea el PERFIL de un usuario (nombre, rol, activo).
  ///
  /// **No crea la cuenta de acceso.** Crear una identidad de Auth necesita la
  /// service key, que no puede viajar en un bundle web — si estuviera en el
  /// `main.dart.js` sería una llave maestra pública, mucho peor que lo que
  /// esto vino a arreglar. La cuenta se crea en el dashboard de Supabase y se
  /// vincula con el bloque 5 de `supabase_migration_auth_identidad.sql`.
  /// Hasta que eso pase, el usuario aparece como SIN CUENTA en la pantalla de
  /// gestión.
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

  /// Cambia la contraseña del usuario logueado en Supabase Auth.
  ///
  /// Verifica la actual antes de cambiar: `updateUser` **no** la pide, así que
  /// sin esta vuelta cualquiera que agarre un celular desbloqueado se queda
  /// con la cuenta.
  ///
  /// Al terminar borra el `password_hash` viejo. Deja de servir para algo y
  /// deja de ser un dato robable: `usuarios` se lee con la publishable key
  /// sola, y un SHA-256 sin sal de una contraseña corta se saca de una tabla
  /// arcoíris. Un hash vacío no coincide con ningún SHA-256, así que además
  /// le cierra a este usuario la puerta del login legacy.
  static Future<ResultadoCambioPassword> cambiarPassword(
      Usuario perfil, String passwordActual, String passwordNueva) async {
    if (_client.auth.currentSession == null) {
      return ResultadoCambioPassword.sinCuentaDeAuth;
    }

    try {
      await _client.auth.signInWithPassword(
        email: mailDe(perfil.usuario),
        password: passwordActual,
      );
    } on AuthException {
      return ResultadoCambioPassword.actualIncorrecta;
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(password: passwordNueva),
      );
    } on AuthException {
      return ResultadoCambioPassword.nuevaRechazada;
    }

    await _client
        .from('usuarios')
        .update({'password_hash': ''}).eq('id', perfil.id);
    perfil.passwordHash = '';

    return ResultadoCambioPassword.ok;
  }
}
