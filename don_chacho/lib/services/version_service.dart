// ============================================================
// AVISO DE VERSIÓN NUEVA (v19.4)
// ============================================================
// POR QUÉ EXISTE: los headers de Vercel ya están bien (`index.html`,
// `flutter_bootstrap.js` y `main.dart.js` se sirven `no-cache`, ver
// web/vercel.json), así que una recarga SIEMPRE trae la versión nueva. El
// problema es que nadie recarga: la app vive como PWA en el iPhone y queda
// abierta días entre un deploy y el siguiente, sin volver a pedir nada.
//
// Entonces el chequeo lo hace la app: compara el `AppConfig.version` que se
// le compiló adentro contra el `app_version.json` que `build_web.sh` escribe
// en cada build. Si difieren, el bundle que está corriendo es viejo.
//
// Este archivo es WEB-ONLY (usa dart:html, igual que ruta_cobranza_service).
// La decisión de si hay que avisar vive en utils/version_check.dart, que no
// importa nada de web y por eso se puede testear.

import 'dart:convert';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import '../utils/app_config.dart';
import '../utils/version_check.dart';

class VersionService {
  /// Lo escribe `build_web.sh` después de compilar, y `web/vercel.json` lo
  /// sirve `no-store` para que el chequeo no se cachee a sí mismo.
  static const String archivo = 'app_version.json';

  /// Qué versión hay publicada ahora mismo en el servidor.
  ///
  /// Devuelve null ante cualquier problema (sin internet, el archivo todavía
  /// no existe, JSON roto). Null significa "no sé", y no saber nunca dispara
  /// el aviso.
  static Future<String?> versionPublicada() async {
    try {
      // Se resuelve contra la URL de la página (`Uri.base`) en vez de mandar
      // una ruta relativa: así anda igual si algún día la app se sirve desde
      // un subpath, y no depende de cómo trate package:http a las relativas.
      //
      // El `?t=` no es decorativo: sin él el navegador puede contestar el
      // chequeo con su propia copia vieja y no enterarse nunca de que hay
      // algo nuevo. Es el error clásico de este tipo de aviso.
      final url = Uri.base.resolve(archivo).replace(
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
      );

      final res = await http.get(
        url,
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return null;

      final map = jsonDecode(res.body);
      if (map is! Map) return null;

      final v = map['version'];
      return v is String ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// ¿El bundle que está corriendo quedó viejo?
  static Future<bool> hayQueActualizar() async {
    return hayVersionNueva(
      corriendo: AppConfig.version,
      publicada: await versionPublicada(),
    );
  }

  /// Trae la versión nueva: limpia lo que pueda estar sirviendo contenido
  /// viejo y recarga.
  ///
  /// Hoy la app se buildea con `--pwa-strategy=none` y el
  /// `flutter_service_worker.js` que sale pesa 0 bytes, así que no hay
  /// service worker. Pero los builds anteriores a v18.10 (mayo 2026) se
  /// hacían con `flutter build web` pelado, que sí registraba uno. Un
  /// dispositivo que usó la app en esa época puede tener todavía ese service
  /// worker viejo sirviéndole assets cacheados, y ahí recargar no alcanza:
  /// hay que desregistrarlo. Por eso la limpieza, aunque hoy parezca de más.
  static Future<void> actualizar() async {
    await _borrarServiceWorkers();
    await _borrarCaches();

    // reload(true) ya no existe en los navegadores modernos; como index.html
    // se sirve no-store, un reload común alcanza.
    html.window.location.reload();
  }

  static Future<void> _borrarServiceWorkers() async {
    try {
      final sw = html.window.navigator.serviceWorker;
      if (sw == null) return;
      final regs = await sw.getRegistrations();
      for (final reg in regs) {
        try {
          await reg.unregister();
        } catch (_) {
          // Uno que no se deja borrar no tiene que frenar a los demás.
        }
      }
    } catch (_) {
      // Navegador sin soporte, contexto inseguro: seguimos igual.
    }
  }

  static Future<void> _borrarCaches() async {
    try {
      final caches = html.window.caches;
      if (caches == null) return;
      final llaves = await caches.keys();
      for (final llave in llaves) {
        try {
          await caches.delete(llave);
        } catch (_) {
          // idem
        }
      }
    } catch (_) {
      // idem
    }
  }
}
