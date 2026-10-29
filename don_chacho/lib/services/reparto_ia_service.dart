// ============================================================
// SERVICIO IA - Carga del reparto por voz/texto
// ============================================================
// Manda la frase dictada (o escrita) por Joaco a la Edge Function
// `parse-reparto`, que la interpreta con Claude y devuelve items
// estructurados para la lista de reparto.
//
// El DÍA viaja en cada item (jueves / viernes / sabado): una misma frase
// puede pedir carne para el jueves y cerdo para el sábado. Si el comando no
// dice ningún día, el item vuelve con `dia` en null y la pantalla se lo
// pregunta al usuario: no se adivina.
//
// El matcheo de nombres lo hace Claude contra la lista de clientes
// reales; acá sólo transportamos y parseamos el JSON. La resolución
// final nombre -> clienteId (con manejo de ambigüedad/no encontrado)
// se hace en la pantalla de reparto.
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

/// Un item interpretado por la IA (todavía sin resolver a clienteId).
class RepartoParseItem {
  /// 'cargar' | 'borrar'
  final String accion;

  /// Nombre EXACTO de la lista de clientes que eligió Claude, o null
  /// si no pudo matchear con seguridad.
  final String? cliente;

  /// 'jueves' | 'viernes' | 'sabado', o null si el comando no lo dijo.
  String? dia;

  final int carne;
  final int cerdo;
  final String sucursal;

  /// 'alta' | 'dudosa'
  final String confianza;

  RepartoParseItem({
    required this.accion,
    required this.cliente,
    required this.dia,
    required this.carne,
    required this.cerdo,
    required this.sucursal,
    required this.confianza,
  });

  bool get esBorrar => accion == 'borrar';

  factory RepartoParseItem.fromMap(Map<String, dynamic> m) {
    final accion = (m['accion'] ?? 'cargar').toString().trim().toLowerCase();
    final cliente = m['cliente'];
    int toInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}'.trim()) ?? 0;
    }

    return RepartoParseItem(
      accion: accion == 'borrar' ? 'borrar' : 'cargar',
      cliente: (cliente is String && cliente.trim().isNotEmpty)
          ? cliente.trim()
          : null,
      dia: _diaValido(m['dia']),
      carne: toInt(m['carne']),
      cerdo: toInt(m['cerdo']),
      sucursal: (m['sucursal'] ?? '').toString().trim(),
      confianza:
          (m['confianza'] ?? 'dudosa').toString().trim().toLowerCase() == 'alta'
              ? 'alta'
              : 'dudosa',
    );
  }
}

/// Devuelve el día si es uno de los tres válidos; si no, null.
/// Tolera que venga con acento o en mayúsculas ("Sábado").
String? _diaValido(dynamic valor) {
  final d = normalizarBusqueda('${valor ?? ''}'.trim());
  return diasReparto.contains(d) ? d : null;
}

/// Resultado del parseo de una frase: los items ya traen su día.
class RepartoParseResult {
  final List<RepartoParseItem> items;

  RepartoParseResult({required this.items});
}

class RepartoIaService {
  // Misma publishable key que usa resolver-maps: la Edge Function la
  // acepta como auth. NO se manda el JWT de sesión.
  static const _publishable =
      'sb_publishable_NQBeEO7_QtErbs056UE1Wg_kJKHZjbf';

  /// Interpreta [texto]. [clientes] es la lista de nombres reales para que
  /// la IA matchee bien. El día sale del propio comando, por eso no se le
  /// manda ninguno.
  ///
  /// Lanza [Exception] si la función falla o no se puede interpretar.
  static Future<RepartoParseResult> interpretar({
    required String texto,
    required List<String> clientes,
  }) async {
    final supabase = Supabase.instance.client;
    final base = supabase.rest.url.replaceAll('/rest/v1', '');

    final res = await http
        .post(
          Uri.parse('$base/functions/v1/parse-reparto'),
          headers: {
            'Content-Type': 'application/json',
            'apikey': _publishable,
            'Authorization': 'Bearer $_publishable',
          },
          body: jsonEncode({
            'texto': texto,
            'clientes': clientes,
          }),
        )
        .timeout(const Duration(seconds: 40));

    if (res.statusCode != 200) {
      throw Exception('El asistente no respondió (${res.statusCode}).');
    }

    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) {
      throw Exception('Respuesta inesperada del asistente.');
    }

    if (data['parse_error'] == true || data['error'] != null) {
      throw Exception('No pude interpretar el pedido. Probá de nuevo.');
    }

    // Día suelto a nivel respuesta: formato viejo de la función. Se usa
    // solo como respaldo para los items que no traigan el suyo.
    final diaGeneral = _diaValido(data['dia']);

    final itemsRaw = data['items'];
    final items = <RepartoParseItem>[];
    if (itemsRaw is List) {
      for (final it in itemsRaw) {
        if (it is Map) {
          items.add(RepartoParseItem.fromMap(Map<String, dynamic>.from(it)));
        }
      }
    }

    for (final it in items) {
      it.dia ??= diaGeneral;
    }
    return RepartoParseResult(items: items);
  }
}
