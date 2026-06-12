// ============================================================
// MAIN - Punto de entrada con Login y Permisos
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'models/models.dart';
import 'providers/app_provider.dart';
import 'services/auth_service.dart';
import 'utils/theme.dart';
import 'screens/home_screen.dart';
import 'screens/vendedores_screen.dart';
import 'screens/clientes_screen.dart';
import 'screens/consultas_screen.dart';
import 'screens/remito_form_screen.dart';
import 'screens/nota_pedido_form_screen.dart';
import 'screens/pago_form_screen.dart';
import 'screens/login_screen.dart';
import 'screens/gestion_usuarios_screen.dart';
import 'screens/bandeja_remitos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('es', null);

  // ── Configurar Supabase ──
  // IMPORTANTE: Reemplazar con tus credenciales reales
  await Supabase.initialize(
    url: 'https://svgvyukjqfjkxtypgobq.supabase.co',
    anonKey: 'sb_publishable_NQBeEO7_QtErbs056UE1Wg_kJKHZjbf',
  );

  runApp(const DonChachoApp());
}

class DonChachoApp extends StatelessWidget {
  const DonChachoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: MaterialApp(
        title: 'Don Chacho - Matarife',
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es'),
        ],
        locale: const Locale('es'),
        home: const AppWrapper(),
      ),
    );
  }
}

/// Wrapper que maneja login/sesión
class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  bool _verificandoSesion = true;
  Usuario? _usuario;

  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    try {
      final user = await AuthService.restaurarSesion();
      if (user != null && mounted) {
        context.read<AppProvider>().setUsuario(user);
        await context.read<AppProvider>().cargarDatos();
      }
      if (mounted) {
        setState(() {
          _usuario = user;
          _verificandoSesion = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _verificandoSesion = false);
      }
    }
  }

  Future<void> _onLogin(dynamic user) async {
    final usuario = user as Usuario;
    setState(() => _verificandoSesion = true);
    context.read<AppProvider>().setUsuario(usuario);
    await context.read<AppProvider>().cargarDatos();
    if (mounted) {
      setState(() {
        _usuario = usuario;
        _verificandoSesion = false;
      });
    }
  }

  void _onLogout() async {
    await AuthService.cerrarSesion();
    setState(() => _usuario = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_verificandoSesion) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_usuario == null) {
      return LoginScreen(onLogin: _onLogin);
    }

    return MainShell(
      usuario: _usuario!,
      onLogout: _onLogout,
    );
  }
}

/// Shell principal con Bottom Navigation + permisos
class MainShell extends StatefulWidget {
  final Usuario usuario;
  final VoidCallback onLogout;

  const MainShell({
    super.key,
    required this.usuario,
    required this.onLogout,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final tiene = app.tienePermiso;

    // Construir lista de pantallas según permisos
    final tabs = <_TabInfo>[];

    // Inicio: siempre visible
    tabs.add(_TabInfo(
      screen: const HomeScreen(),
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Inicio',
    ));

    // Vendedores: solo si gestionar_vendedores
    if (tiene('gestionar_vendedores')) {
      tabs.add(_TabInfo(
        screen: const VendedoresScreen(),
        icon: Icons.people_outline,
        activeIcon: Icons.people,
        label: 'Vendedores',
      ));
    }

    // Clientes: solo si gestionar_clientes
    if (tiene('gestionar_clientes')) {
      tabs.add(_TabInfo(
        screen: const ClientesScreen(),
        icon: Icons.store_outlined,
        activeIcon: Icons.store,
        label: 'Clientes',
      ));
    }

    // Consultas: solo si ver_consultas
    if (tiene('ver_consultas')) {
      tabs.add(_TabInfo(
        screen: const ConsultasScreen(),
        icon: Icons.bar_chart_outlined,
        activeIcon: Icons.bar_chart,
        label: 'Consultas',
      ));
    }

    // Asegurar que el índice no se salga de rango
    if (_currentIndex >= tabs.length) {
      _currentIndex = 0;
    }

    final tieneFab = tiene('crear_remito') || tiene('crear_pago');

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs.map((t) => t.screen).toList(),
      ),
      floatingActionButton: tieneFab
          ? FloatingActionButton(
              onPressed: () => _mostrarAcciones(context),
              tooltip: 'Nuevo',
              child: const Icon(Icons.add, size: 32),
            )
          : null,
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade300, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 88,
            child: Row(
              children: [
                for (int i = 0; i < tabs.length; i++) ...[
                  if (i == tabs.length ~/ 2 && tieneFab)
                    const SizedBox(width: 72),
                  _NavItem(
                    icon: tabs[i].icon,
                    activeIcon: tabs[i].activeIcon,
                    label: tabs[i].label,
                    selected: _currentIndex == i,
                    onTap: () => setState(() => _currentIndex = i),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _mostrarAcciones(BuildContext context) {
    final app = context.read<AppProvider>();
    final tiene = app.tienePermiso;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Opciones',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (tiene('crear_remito'))
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primary.withOpacity(0.1),
                    child: Icon(
                      app.esAdmin
                          ? Icons.receipt_long
                          : Icons.assignment_outlined,
                      color: AppTheme.primary,
                    ),
                  ),
                  title: Text(app.esAdmin
                      ? 'Nuevo remito'
                      : 'Nueva nota de pedido'),
                  subtitle: Text(app.esAdmin
                      ? 'Cargar venta de medias'
                      : 'Cargar pedido para confirmar'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => app.esAdmin
                            ? const RemitoFormScreen()
                            : const NotaPedidoFormScreen(),
                      ),
                    );
                  },
                ),
              if (tiene('crear_pago')) ...[
                const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.success.withOpacity(0.1),
                    child: const Icon(Icons.payments,
                        color: AppTheme.success),
                  ),
                  title: const Text('Registrar pago'),
                  subtitle: const Text('Cobrar a cliente'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PagoFormScreen()),
                    );
                  },
                ),
              ],
              if (tiene('confirmar_remito')) ...[
                const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.warning.withOpacity(0.1),
                    child: const Icon(Icons.fact_check,
                        color: AppTheme.warning),
                  ),
                  title: Row(
                    children: [
                      const Text('Confirmar remitos'),
                      const SizedBox(width: 8),
                      Builder(builder: (context) {
                        final count = app.remitos
                                .where((r) => r.esPendiente)
                                .length +
                            app.notasPedidoPendientes.length;
                        if (count == 0) return const SizedBox.shrink();
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        );
                      }),
                    ],
                  ),
                  subtitle: const Text('Aprobar/rechazar remitos'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => BandejaRemitosScreen(
                              usuarioActual: widget.usuario)),
                    );
                  },
                ),
              ],
              if (tiene('gestionar_usuarios')) ...[
                const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.info.withOpacity(0.1),
                    child: const Icon(Icons.admin_panel_settings,
                        color: AppTheme.info),
                  ),
                  title: const Text('Usuarios y Roles'),
                  subtitle: const Text('Gestionar accesos'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GestionUsuariosScreen(
                              usuarioActual: widget.usuario)),
                    );
                  },
                ),
              ],
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.textHint.withOpacity(0.1),
                  child: const Icon(Icons.logout,
                      color: AppTheme.textHint),
                ),
                title: const Text('Cerrar sesión'),
                subtitle: Text(
                    '${widget.usuario.nombreCompleto} (${widget.usuario.rol?.nombre ?? ""})',
                    style: const TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onLogout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabInfo {
  final Widget screen;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  _TabInfo({
    required this.screen,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.textHint;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? activeIcon : icon,
                size: 32,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
