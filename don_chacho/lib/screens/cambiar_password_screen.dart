// ============================================================
// CAMBIAR CONTRASEÑA
// ============================================================
// Hace falta para la migración a Supabase Auth: las contraseñas viejas no se
// pueden migrar (eran SHA-256 sin sal, Auth usa bcrypt), así que cada usuario
// arranca con una contraseña temporal que le pasa Mili y la cambia acá la
// primera vez que entra.
//
// Está para todos los roles, igual que Soporte: una contraseña que solo
// puede cambiar el admin es una contraseña que no se cambia nunca.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import '../utils/theme.dart';

class CambiarPasswordScreen extends StatefulWidget {
  const CambiarPasswordScreen({super.key});

  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _repetirCtrl = TextEditingController();
  bool _guardando = false;
  String? _error;
  bool _ocultar = true;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _repetirCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final perfil = context.read<AppProvider>().usuarioActual;
    if (perfil == null) return;

    final actual = _actualCtrl.text;
    final nueva = _nuevaCtrl.text;

    if (actual.isEmpty || nueva.isEmpty) {
      setState(() => _error = 'Completá las dos contraseñas');
      return;
    }
    if (nueva.length < AuthService.minPassword) {
      setState(() => _error =
          'La nueva tiene que tener al menos ${AuthService.minPassword} caracteres');
      return;
    }
    if (nueva != _repetirCtrl.text) {
      setState(() => _error = 'La repetición no coincide');
      return;
    }
    if (nueva == actual) {
      setState(() => _error = 'La nueva tiene que ser distinta de la actual');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final res = await AuthService.cambiarPassword(perfil, actual, nueva);
      if (!mounted) return;

      if (res == ResultadoCambioPassword.ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contraseña cambiada'),
            backgroundColor: AppTheme.success,
          ),
        );
        return;
      }

      final mensaje = switch (res) {
        ResultadoCambioPassword.actualIncorrecta =>
          'La contraseña actual no es correcta',
        ResultadoCambioPassword.sinCuentaDeAuth =>
          'Tu cuenta de acceso todavía no está habilitada. Avisale a quien '
              'administra el sistema.',
        ResultadoCambioPassword.nuevaRechazada =>
          'La contraseña nueva no fue aceptada. Probá con otra más larga.',
        ResultadoCambioPassword.ok => '',
      };
      setState(() {
        _guardando = false;
        _error = mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo cambiar: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = context.watch<AppProvider>().usuarioActual;

    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar contraseña')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (perfil != null)
                Text(
                  'Usuario: ${perfil.usuario}',
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),
              const SizedBox(height: 20),
              TextField(
                controller: _actualCtrl,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nuevaCtrl,
                decoration: InputDecoration(
                  labelText: 'Contraseña nueva',
                  prefixIcon: const Icon(Icons.lock_reset),
                  helperText:
                      'Mínimo ${AuthService.minPassword} caracteres',
                  suffixIcon: IconButton(
                    icon: Icon(_ocultar
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(() => _ocultar = !_ocultar),
                  ),
                ),
                obscureText: _ocultar,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _repetirCtrl,
                decoration: const InputDecoration(
                  labelText: 'Repetir la nueva',
                  prefixIcon: Icon(Icons.lock_reset),
                ),
                obscureText: _ocultar,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _guardar(),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                        color: AppTheme.danger, fontSize: 13),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Guardar', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
