// ============================================================
// SERVICIO DE SOPORTE
// ============================================================
// El ticket se guarda en Supabase (fuente de la verdad) y WhatsApp es solo
// el aviso. Si el usuario no llega a mandar el mensaje, el reclamo ya quedó
// registrado en la bandeja.
//
// El adjunto va a un bucket privado. En la tabla se guarda el path, no la
// URL: los links firmados se generan en el momento, así un link que se
// filtró en un reenvío de WhatsApp caduca solo.
// ============================================================

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../utils/app_config.dart';
import '../utils/formatters.dart';

class SoporteService {
  static const String _bucket = 'soporte-adjuntos';

  /// Vigencia del link que viaja por WhatsApp. La bandeja siempre firma uno
  /// nuevo, así que esto solo limita la vida del que quedó en el chat.
  static const int _vigenciaLinkSegundos = 60 * 60 * 24 * 90; // 90 días

  static const _uuid = Uuid();

  /// Módulos del sistema, para que el reclamo venga ubicado y no haya que
  /// adivinar dónde falló.
  static const List<String> modulos = [
    'Inicio / Dashboard',
    'Remitos',
    'Notas de pedido',
    'Confirmar remitos',
    'Pagos',
    'Notas de crédito / débito',
    'Clientes',
    'Vendedores',
    'Lista de reparto',
    'Asistente de reparto',
    'Consultas / Reportes',
    'Costos de la semana',
    'Usuarios y roles',
    'Ingreso a la app',
    'Otro',
  ];

  final SupabaseClient _client = Supabase.instance.client;

  /// Plataforma donde corre la app, para distinguir un iPhone de una PC.
  static String get plataforma {
    final p = defaultTargetPlatform.name;
    return kIsWeb ? 'web/$p' : p;
  }

  /// Sube la imagen y devuelve el path guardable en el ticket.
  Future<String> subirAdjunto({
    required Uint8List bytes,
    required String nombreArchivo,
  }) async {
    final ext = nombreArchivo.contains('.')
        ? nombreArchivo.split('.').last.toLowerCase()
        : 'jpg';
    final path = '${_uuid.v4()}.$ext';
    await _client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: _mimePorExtension(ext)),
        );
    return path;
  }

  /// Link firmado para mirar el adjunto.
  Future<String> urlAdjunto(String path) =>
      _client.storage.from(_bucket).createSignedUrl(path, _vigenciaLinkSegundos);

  /// Abre WhatsApp con el ticket ya escrito. Devuelve false si no hay número
  /// de soporte configurado o si el dispositivo no puede abrir el link.
  Future<bool> avisarPorWhatsapp(TicketSoporte ticket) async {
    if (!AppConfig.tieneWhatsappSoporte) return false;

    final numero =
        AppConfig.soporteWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    if (numero.isEmpty) return false;

    String? linkAdjunto;
    if (ticket.tieneAdjunto) {
      try {
        linkAdjunto = await urlAdjunto(ticket.adjuntoPath!);
      } catch (_) {
        // Sin link igual se manda el aviso: la foto está en la bandeja.
      }
    }

    final uri = Uri.https(
      'wa.me',
      '/$numero',
      {'text': _mensajeWhatsapp(ticket, linkAdjunto: linkAdjunto)},
    );
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String _mensajeWhatsapp(TicketSoporte ticket, {String? linkAdjunto}) {
    final lineas = <String>[
      'SOPORTE — ${AppConfig.clienteNombre}',
      'Ticket ${ticket.numeroFormateado}',
      if (ticket.bloqueante) 'URGENTE: no puede seguir trabajando',
      'Módulo: ${ticket.modulo}',
      '',
      ticket.descripcion,
      '',
      if (linkAdjunto != null) 'Foto: $linkAdjunto',
      if (ticket.tieneAdjunto && linkAdjunto == null)
        'Adjuntó una foto (verla en la bandeja de Soporte)',
      'Usuario: ${ticket.reportadoPor ?? '—'}'
          '${(ticket.rol ?? '').isEmpty ? '' : ' (${ticket.rol})'}',
      'Fecha: ${formatFechaHora(ticket.creadoEn)}',
      'App: ${ticket.appVersion ?? '—'} · ${ticket.plataforma ?? '—'}',
    ];
    return lineas.join('\n');
  }

  static String _mimePorExtension(String ext) => switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        _ => 'image/jpeg',
      };
}
