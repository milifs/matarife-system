// ============================================================
// REPORTAR UN PROBLEMA (SOPORTE)
// ============================================================
// El usuario elige en qué parte del sistema falló, lo describe y puede
// adjuntar una foto de la pantalla. El resto del contexto (quién, cuándo,
// versión, dispositivo) lo captura la app sola.
// Al guardar se abre WhatsApp con el reclamo ya escrito; el ticket queda
// registrado igual si no llega a mandarlo.
// ============================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/soporte_service.dart';
import '../utils/app_config.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class SoporteFormScreen extends StatefulWidget {
  const SoporteFormScreen({super.key});

  @override
  State<SoporteFormScreen> createState() => _SoporteFormScreenState();
}

class _SoporteFormScreenState extends State<SoporteFormScreen> {
  final _db = DatabaseService();
  final _soporte = SoporteService();
  final _descripcionCtrl = TextEditingController();

  String? _modulo;
  bool _bloqueante = false;
  bool _enviando = false;

  Uint8List? _adjuntoBytes;
  String? _adjuntoNombre;

  List<TicketSoporte> _mios = [];

  @override
  void initState() {
    super.initState();
    _cargarMios();
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarMios() async {
    final usuario = context.read<AppProvider>().usuarioActual;
    if (usuario == null) return;
    try {
      final tickets =
          await _db.getTicketsSoporte(reportadoPor: usuario.nombreCompleto);
      if (mounted) setState(() => _mios = tickets.take(5).toList());
    } catch (_) {
      // Sin historial el formulario sigue siendo usable.
    }
  }

  bool get _puedeEnviar =>
      !_enviando &&
      _modulo != null &&
      _descripcionCtrl.text.trim().length >= 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reportar un problema')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.infoBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.support_agent, size: 20, color: AppTheme.info),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Contá qué pasó y, si podés, sacale una foto a la '
                    'pantalla. Queda registrado y te vamos a responder acá '
                    'mismo cuando esté resuelto.',
                    style: TextStyle(fontSize: 13, color: AppTheme.info),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Módulo ──
          DropdownButtonFormField<String>(
            initialValue: _modulo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '¿En qué parte del sistema?',
            ),
            items: [
              for (final m in SoporteService.modulos)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _modulo = v),
          ),
          const SizedBox(height: 16),

          // ── Descripción ──
          TextField(
            controller: _descripcionCtrl,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '¿Qué pasó?',
              hintText: 'Ej: al guardar un pago de un cliente me tira error '
                  'y el saldo no se actualiza.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Contá qué querías hacer y qué pasó en su lugar.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // ── Bloqueante ──
          Card(
            child: SwitchListTile(
              value: _bloqueante,
              onChanged: (v) => setState(() => _bloqueante = v),
              title: const Text('No puedo seguir trabajando',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text('Marcalo solo si te frena el trabajo',
                  style: TextStyle(fontSize: 12)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Adjunto ──
          if (_adjuntoBytes == null)
            OutlinedButton.icon(
              onPressed: _elegirImagen,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text('Adjuntar foto de la pantalla'),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _adjuntoBytes!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 80,
                          alignment: Alignment.center,
                          color: AppTheme.background,
                          child: const Text(
                            'Foto adjuntada (no se puede previsualizar)',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _adjuntoNombre ?? 'foto',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _adjuntoBytes = null;
                            _adjuntoNombre = null;
                          }),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Quitar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: _puedeEnviar ? _enviar : null,
            icon: _enviando
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send, size: 18),
            label: Text(AppConfig.tieneWhatsappSoporte
                ? 'Enviar a soporte'
                : 'Registrar el problema'),
          ),
          const SizedBox(height: 10),
          if (AppConfig.tieneWhatsappSoporte)
            const Text(
              'Se abre WhatsApp con el reclamo ya escrito: solo tenés que '
              'apretar enviar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),

          // ── Tus reclamos anteriores ──
          if (_mios.isNotEmpty) ...[
            const SizedBox(height: 32),
            const Text('Tus reclamos',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            for (final t in _mios) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(t.numeroFormateado,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          StatusPill(
                            text: t.estadoLabel,
                            type: switch (t.estado) {
                              'resuelto' => StatusType.success,
                              'en_revision' => StatusType.info,
                              _ => StatusType.warning,
                            },
                          ),
                          const Spacer(),
                          Text(formatFechaCorta(t.creadoEn),
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textHint)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${t.modulo} — ${t.descripcion}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                      if (t.respuesta.trim().isNotEmpty) ...[
                        const Divider(height: 16),
                        Text('Respuesta: ${t.respuesta}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.success)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _elegirImagen() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _adjuntoBytes = bytes;
      _adjuntoNombre = picked.name;
    });
  }

  Future<void> _enviar() async {
    setState(() => _enviando = true);
    final app = context.read<AppProvider>();

    String? adjuntoPath;
    if (_adjuntoBytes != null) {
      try {
        adjuntoPath = await _soporte.subirAdjunto(
          bytes: _adjuntoBytes!,
          nombreArchivo: _adjuntoNombre ?? 'foto.jpg',
        );
      } catch (e) {
        // La foto es un plus: si falla la subida, igual mandamos el reclamo.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo subir la foto, se envía sin ella: $e'),
              backgroundColor: AppTheme.warning,
            ),
          );
        }
      }
    }

    final ticket = TicketSoporte(
      modulo: _modulo!,
      descripcion: _descripcionCtrl.text.trim(),
      bloqueante: _bloqueante,
      adjuntoPath: adjuntoPath,
      reportadoPor: app.usuarioActual?.nombreCompleto,
      rol: app.usuarioActual?.rol?.nombre,
      appVersion: AppConfig.version,
      plataforma: SoporteService.plataforma,
    );

    TicketSoporte guardado;
    try {
      guardado = await _db.insertTicketSoporte(ticket);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al registrar el problema: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final abrioWhatsapp = await _soporte.avisarPorWhatsapp(guardado);

    if (!mounted) return;
    setState(() => _enviando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(abrioWhatsapp
            ? 'Reclamo ${guardado.numeroFormateado} registrado. '
                'Apretá enviar en WhatsApp.'
            : 'Reclamo ${guardado.numeroFormateado} registrado.'),
        backgroundColor: AppTheme.success,
      ),
    );
    Navigator.pop(context, guardado);
  }
}
