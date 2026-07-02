// ============================================================
// SERVICIO DE RUTA DE COBRANZA
// Arma una ruta optimizada (vecino más cercano) para visitar
// clientes deudores usando su ubicación de Google Maps.
// App web-only → usa geolocalización del navegador (dart:html).
// ============================================================

import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

/// Coordenada geográfica simple.
class Coord {
  final double lat;
  final double lng;
  const Coord(this.lat, this.lng);

  @override
  String toString() => '$lat,$lng';
}

/// Una parada de la ruta: el cliente, sus coordenadas (si se pudieron
/// obtener) y el texto que se usará como punto en el link de Maps.
class ParadaRuta {
  final Cliente cliente;
  final Coord? coord;

  ParadaRuta(this.cliente, this.coord);

  bool get tieneCoord => coord != null;

  /// Punto a usar en el link de Google Maps: coordenadas si las hay,
  /// si no la dirección de texto libre. Null si no hay ninguna.
  String? get puntoUrl {
    if (coord != null) return coord.toString();
    final dir = cliente.ubicacion.trim();
    if (dir.isNotEmpty) return dir;
    return null;
  }
}

class RutaCobranzaService {
  // ── Geolocalización del navegador ──────────────────────────
  /// Pide la ubicación GPS actual. Devuelve null si el usuario la niega,
  /// no está disponible, o tarda demasiado.
  static Future<Coord?> ubicacionActual() async {
    try {
      final geo = html.window.navigator.geolocation;
      final pos = await geo.getCurrentPosition(
        enableHighAccuracy: true,
        timeout: const Duration(seconds: 10),
      );
      final c = pos.coords;
      if (c == null) return null;
      final lat = c.latitude;
      final lng = c.longitude;
      if (lat == null || lng == null) return null;
      return Coord(lat.toDouble(), lng.toDouble());
    } catch (_) {
      return null;
    }
  }

  // ── Extracción de coordenadas ──────────────────────────────
  /// Intenta sacar coordenadas de la ubicación del cliente:
  /// primero del link de Maps, después del texto libre.
  static Coord? coordsDeCliente(Cliente c) {
    return _parseCoords(c.ubicacionUrl) ?? _parseCoords(c.ubicacion);
  }

  /// Extrae un par lat,lng de un texto (link de Maps o dirección).
  /// Soporta los formatos más comunes de URLs de Google Maps.
  /// Los links cortos (maps.app.goo.gl/...) NO traen coordenadas.
  static Coord? _parseCoords(String? texto) {
    if (texto == null || texto.trim().isEmpty) return null;
    final s = texto.trim();

    // !3d<lat>!4d<lng>  (URLs "place" completas)
    final m3d4d = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(s);
    if (m3d4d != null) return _build(m3d4d.group(1), m3d4d.group(2));

    // @<lat>,<lng>  (URL con vista de mapa)
    final mAt = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(s);
    if (mAt != null) return _build(mAt.group(1), mAt.group(2));

    // ?q=  / &query=  / ?ll=  / &daddr=  / &destination=  / &center=
    final mParam = RegExp(
      r'[?&](?:q|query|ll|daddr|destination|center)=(-?\d+\.\d+),(-?\d+\.\d+)',
    ).firstMatch(s);
    if (mParam != null) return _build(mParam.group(1), mParam.group(2));

    // Texto que es directamente "lat, lng"
    final mPar = RegExp(r'^\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*$')
        .firstMatch(s);
    if (mPar != null) return _build(mPar.group(1), mPar.group(2));

    // Formato DMS (grados/minutos/segundos), ej: 24°59'04.1"S 65°22'17.8"W
    // Aparece en URLs "place" cargadas desde la app de Google Maps.
    final dms = _parseDms(s);
    if (dms != null) return dms;

    return null;
  }

  /// Extrae coordenadas en formato DMS de un texto (puede venir url-encoded).
  /// Busca dos componentes: primero lat (N/S), después lng (E/W).
  static Coord? _parseDms(String texto) {
    // Decodifica %C2%B0 (°), %22 ("), etc. si viene de una URL.
    var s = texto;
    try {
      s = Uri.decodeFull(texto);
    } catch (_) {}

    // <grados>°<minutos>'<segundos>"<hemisferio>
    final re = RegExp(
      r"(\d{1,3})\s*[°º]\s*(\d{1,2})\s*['′]\s*([\d.]+)\s*[\x22″]\s*([NSEWnsew])",
    );
    final matches = re.allMatches(s).toList();
    if (matches.length < 2) return null;

    double? lat, lng;
    for (final m in matches) {
      final deg = double.tryParse(m.group(1) ?? '');
      final min = double.tryParse(m.group(2) ?? '');
      final sec = double.tryParse(m.group(3) ?? '');
      final hemi = (m.group(4) ?? '').toUpperCase();
      if (deg == null || min == null || sec == null) continue;
      var val = deg + min / 60 + sec / 3600;
      if (hemi == 'S' || hemi == 'W') val = -val;
      if (hemi == 'N' || hemi == 'S') {
        lat ??= val;
      } else {
        lng ??= val;
      }
    }
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return Coord(lat, lng);
  }

  static Coord? _build(String? a, String? b) {
    final lat = double.tryParse(a ?? '');
    final lng = double.tryParse(b ?? '');
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return Coord(lat, lng);
  }

  // ── Resolución de links cortos vía Edge Function ───────────
  /// Los links cortos (maps.app.goo.gl/...) no traen coordenadas y el
  /// navegador no puede seguir el redirect por CORS. Esta función manda
  /// los links a la Edge Function que los resuelve del lado del servidor.
  /// Devuelve un mapa url→Coord solo con los que se pudieron resolver.
  static Future<Map<String, Coord>> resolverLinks(List<String> urls) async {
    final limpias = urls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    if (limpias.isEmpty) return {};

    try {
      final supabase = Supabase.instance.client;
      final base = supabase.rest.url.replaceAll('/rest/v1', '');
      // La función usa auth "publishable": mandamos siempre la publishable
      // key (no el JWT de la sesión, que la función rechazaría).
      const publishable = 'sb_publishable_NQBeEO7_QtErbs056UE1Wg_kJKHZjbf';

      final res = await http
          .post(
            Uri.parse('$base/functions/v1/resolver-maps'),
            headers: {
              'Content-Type': 'application/json',
              'apikey': publishable,
              'Authorization': 'Bearer $publishable',
            },
            body: jsonEncode({'urls': limpias}),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode != 200) return {};

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final resultados = data['results'];
      if (resultados is! List) return {};

      final mapa = <String, Coord>{};
      for (final r in resultados) {
        if (r is! Map) continue;
        final url = r['url'];
        final lat = r['lat'];
        final lng = r['lng'];
        if (url is String && lat is num && lng is num) {
          mapa[url] = Coord(lat.toDouble(), lng.toDouble());
        }
      }
      return mapa;
    } catch (_) {
      return {};
    }
  }

  /// Arma las paradas de una lista de clientes, resolviendo primero las
  /// coordenadas localmente y, para los que no se pudieron, consultando
  /// la Edge Function (links cortos). Una sola llamada de red para todos.
  static Future<List<ParadaRuta>> construirParadas(List<Cliente> clientes) async {
    // Coord local (si se pudo) o null.
    final localCoords = <Cliente, Coord?>{
      for (final c in clientes) c: coordsDeCliente(c),
    };

    // Clientes sin coord local pero con algún link/dirección para resolver.
    final aResolver = <String>[];
    for (final c in clientes) {
      if (localCoords[c] != null) continue;
      final link = c.ubicacionUrl.trim();
      if (link.isNotEmpty) aResolver.add(link);
    }

    final resueltas = await resolverLinks(aResolver);

    return clientes.map((c) {
      final local = localCoords[c];
      if (local != null) return ParadaRuta(c, local);
      final link = c.ubicacionUrl.trim();
      final remota = resueltas[link];
      return ParadaRuta(c, remota);
    }).toList();
  }

  // ── Ordenamiento por cercanía (vecino más cercano) ─────────
  /// Ordena las paradas empezando por la más cercana al [origen].
  /// Las paradas sin coordenadas se dejan al final en su orden original.
  /// Si no hay [origen], devuelve las paradas sin reordenar.
  static List<ParadaRuta> ordenarPorCercania(
    List<ParadaRuta> paradas,
    Coord? origen,
  ) {
    final conCoord = paradas.where((p) => p.tieneCoord).toList();
    final sinCoord = paradas.where((p) => !p.tieneCoord).toList();

    if (origen == null || conCoord.isEmpty) {
      return [...conCoord, ...sinCoord];
    }

    final ordenadas = <ParadaRuta>[];
    final pendientes = [...conCoord];
    Coord actual = origen;

    while (pendientes.isNotEmpty) {
      pendientes.sort((a, b) => _distancia(actual, a.coord!)
          .compareTo(_distancia(actual, b.coord!)));
      final siguiente = pendientes.removeAt(0);
      ordenadas.add(siguiente);
      actual = siguiente.coord!;
    }

    return [...ordenadas, ...sinCoord];
  }

  /// Distancia aproximada (equirectangular) suficiente para ordenar.
  static double _distancia(Coord a, Coord b) {
    const rad = math.pi / 180;
    final x = (b.lng - a.lng) * rad * math.cos((a.lat + b.lat) / 2 * rad);
    final y = (b.lat - a.lat) * rad;
    return x * x + y * y;
  }

  // ── Construcción del link de Google Maps ───────────────────
  /// Arma la URL de direcciones de Google Maps con todas las paradas.
  /// La primera parada es el destino final; el resto son waypoints en
  /// orden. Si hay [origen] se usa como punto de partida.
  static String construirUrl(List<ParadaRuta> paradasOrdenadas, Coord? origen) {
    final puntos = paradasOrdenadas
        .map((p) => p.puntoUrl)
        .whereType<String>()
        .toList();

    final params = <String, String>{
      'api': '1',
      'travelmode': 'driving',
    };
    if (origen != null) params['origin'] = origen.toString();

    if (puntos.isNotEmpty) {
      params['destination'] = puntos.last;
      final waypoints = puntos.sublist(0, puntos.length - 1);
      if (waypoints.isNotEmpty) {
        params['waypoints'] = waypoints.join('|');
      }
    }

    return Uri.https('www.google.com', '/maps/dir/', params).toString();
  }
}
