// ============================================================
// GESTIÓN DE USUARIOS Y ROLES
// ============================================================

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../utils/theme.dart';

class GestionUsuariosScreen extends StatefulWidget {
  final Usuario usuarioActual;
  const GestionUsuariosScreen({super.key, required this.usuarioActual});

  @override
  State<GestionUsuariosScreen> createState() => _GestionUsuariosScreenState();
}

class _GestionUsuariosScreenState extends State<GestionUsuariosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Usuario> _usuarios = [];
  List<Rol> _roles = [];
  List<Permiso> _permisos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    _usuarios = await AuthService.getUsuarios();
    _roles = await AuthService.getRoles();
    _permisos = await AuthService.getPermisos();
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios y Roles'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textHint,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Usuarios'),
            Tab(text: 'Roles'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildUsuariosTab(),
                _buildRolesTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════
  // TAB USUARIOS
  // ═══════════════════════════════════════════
  Widget _buildUsuariosTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: () => _editarUsuario(null),
            icon: const Icon(Icons.person_add),
            label: const Text('Nuevo usuario'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _usuarios.length,
            itemBuilder: (context, i) {
              final u = _usuarios[i];
              final esMismoUsuario = u.id == widget.usuarioActual.id;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: u.activo
                        ? AppTheme.primary.withOpacity(0.1)
                        : AppTheme.textHint.withOpacity(0.1),
                    child: Icon(
                      u.activo ? Icons.person : Icons.person_off,
                      color: u.activo
                          ? AppTheme.primary
                          : AppTheme.textHint,
                    ),
                  ),
                  title: Text(u.nombreCompleto,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${u.usuario} · ${u.rol?.nombre ?? "Sin rol"}${!u.activo ? " · INACTIVO" : ""}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editarUsuario(u),
                      ),
                      if (!esMismoUsuario)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: AppTheme.danger),
                          onPressed: () => _eliminarUsuario(u),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editarUsuario(Usuario? existente) async {
    final result = await showModalBottomSheet<Usuario>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _UsuarioEditor(
        existente: existente,
        roles: _roles,
        esEdicionPropia: existente?.id == widget.usuarioActual.id,
      ),
    );

    if (result == null) return;

    if (existente != null) {
      await AuthService.actualizarUsuario(result);
    } else {
      await AuthService.crearUsuario(result);
    }
    await _cargarDatos();
  }

  Future<void> _eliminarUsuario(Usuario u) async {
    // Protección: no eliminar el propio usuario
    if (u.id == widget.usuarioActual.id) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
            '¿Seguro que querés eliminar a "${u.nombreCompleto}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    await AuthService.eliminarUsuario(u.id);
    await _cargarDatos();
  }

  // ═══════════════════════════════════════════
  // TAB ROLES
  // ═══════════════════════════════════════════
  Widget _buildRolesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: () => _editarRol(null),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo rol'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _roles.length,
            itemBuilder: (context, i) {
              final r = _roles[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: r.esAdmin
                        ? AppTheme.primary.withOpacity(0.1)
                        : AppTheme.info.withOpacity(0.1),
                    child: Icon(
                      r.esAdmin ? Icons.admin_panel_settings : Icons.badge,
                      color: r.esAdmin ? AppTheme.primary : AppTheme.info,
                    ),
                  ),
                  title: Text(r.nombre,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    r.esAdmin
                        ? 'Administrador (todos los permisos)'
                        : '${r.permisoIds.length} permisos',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editarRol(r),
                      ),
                      if (!r.esAdmin)
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: AppTheme.danger),
                          onPressed: () => _eliminarRol(r),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editarRol(Rol? existente) async {
    final result = await showModalBottomSheet<Rol>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RolEditor(
        existente: existente,
        permisos: _permisos,
      ),
    );

    if (result == null) return;

    if (existente != null) {
      await AuthService.actualizarRol(result);
    } else {
      await AuthService.crearRol(result);
    }
    await _cargarDatos();
  }

  Future<void> _eliminarRol(Rol r) async {
    // Verificar que no haya usuarios con este rol
    final usuariosConRol =
        _usuarios.where((u) => u.rolId == r.id).toList();
    if (usuariosConRol.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'No se puede eliminar: ${usuariosConRol.length} usuario(s) usan este rol'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar rol'),
        content: Text('¿Seguro que querés eliminar el rol "${r.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    await AuthService.eliminarRol(r.id);
    await _cargarDatos();
  }
}

// ─────────────────────────────────────────────
// EDITOR DE USUARIO (modal)
// ─────────────────────────────────────────────
class _UsuarioEditor extends StatefulWidget {
  final Usuario? existente;
  final List<Rol> roles;
  final bool esEdicionPropia;

  const _UsuarioEditor({
    this.existente,
    required this.roles,
    this.esEdicionPropia = false,
  });

  @override
  State<_UsuarioEditor> createState() => _UsuarioEditorState();
}

class _UsuarioEditorState extends State<_UsuarioEditor> {
  final _nombreCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _rolId;
  bool _activo = true;

  @override
  void initState() {
    super.initState();
    if (widget.existente != null) {
      _nombreCtrl.text = widget.existente!.nombreCompleto;
      _usuarioCtrl.text = widget.existente!.usuario;
      _rolId = widget.existente!.rolId;
      _activo = widget.existente!.activo;
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existente != null
                  ? 'Editar usuario'
                  : 'Nuevo usuario',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nombre completo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usuarioCtrl,
              decoration: const InputDecoration(
                  labelText: 'Usuario (para login)'),
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              decoration: InputDecoration(
                labelText: widget.existente != null
                    ? 'Nueva contraseña (dejar vacío para no cambiar)'
                    : 'Contraseña',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _rolId,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: widget.roles
                  .map((r) => DropdownMenuItem(
                        value: r.id,
                        child: Text(r.nombre),
                      ))
                  .toList(),
              onChanged: widget.esEdicionPropia
                  ? null // No puede cambiar su propio rol
                  : (v) => setState(() => _rolId = v),
            ),
            const SizedBox(height: 12),
            if (!widget.esEdicionPropia)
              SwitchListTile(
                title: const Text('Activo'),
                value: _activo,
                onChanged: (v) => setState(() => _activo = v),
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _guardar,
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _guardar() {
    if (_nombreCtrl.text.trim().isEmpty ||
        _usuarioCtrl.text.trim().isEmpty ||
        _rolId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completá todos los campos'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (widget.existente == null && _passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La contraseña es obligatoria'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final passwordHash = _passwordCtrl.text.isNotEmpty
        ? AuthService.hashPassword(_passwordCtrl.text)
        : widget.existente!.passwordHash;

    final usuario = Usuario(
      id: widget.existente?.id,
      usuario: _usuarioCtrl.text.trim().toLowerCase(),
      passwordHash: passwordHash,
      rolId: _rolId!,
      nombreCompleto: _nombreCtrl.text.trim(),
      activo: _activo,
    );

    Navigator.pop(context, usuario);
  }
}

// ─────────────────────────────────────────────
// EDITOR DE ROL (modal)
// ─────────────────────────────────────────────
class _RolEditor extends StatefulWidget {
  final Rol? existente;
  final List<Permiso> permisos;

  const _RolEditor({this.existente, required this.permisos});

  @override
  State<_RolEditor> createState() => _RolEditorState();
}

class _RolEditorState extends State<_RolEditor> {
  final _nombreCtrl = TextEditingController();
  final Set<String> _permisosSeleccionados = {};

  @override
  void initState() {
    super.initState();
    if (widget.existente != null) {
      _nombreCtrl.text = widget.existente!.nombre;
      _permisosSeleccionados.addAll(widget.existente!.permisoIds);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existente != null ? 'Editar rol' : 'Nuevo rol',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nombreCtrl,
              decoration:
                  const InputDecoration(labelText: 'Nombre del rol'),
            ),
            const SizedBox(height: 16),
            const Text('Permisos',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            ...widget.permisos.map((p) => CheckboxListTile(
                  title: Text(p.nombre,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(p.descripcion,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  value: _permisosSeleccionados.contains(p.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _permisosSeleccionados.add(p.id);
                      } else {
                        _permisosSeleccionados.remove(p.id);
                      }
                    });
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                )),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _guardar,
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _guardar() {
    if (_nombreCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresá un nombre para el rol'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final rol = Rol(
      id: widget.existente?.id,
      nombre: _nombreCtrl.text.trim(),
      esAdmin: widget.existente?.esAdmin ?? false,
      permisoIds: _permisosSeleccionados.toList(),
    );

    Navigator.pop(context, rol);
  }
}
