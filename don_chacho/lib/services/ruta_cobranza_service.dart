// ============================================================
// SERVICIO DE RUTA DE COBRANZA
// Arma una ruta optimizada (vecino más cercano) para visitar
// clientes deudores usando su ubicación de Google Maps.
// App web-only → usa geolocalización del navegador (dart:html).
// ============================================================

import 'dart:html' as html;
import 'dart:math' as math;
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

    return null;
  }

  static Coord? _build(String? a, String? b) {
    final lat = double.tryParse(a ?? '');
    final lng = double.tryParse(b ?? '');
    if (lat == null || lng == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return Coord(lat, lng);
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
