// ============================================================
// SERVICIO OCR - Lee fotos de remitos via Supabase Edge Function
// ============================================================
// Ahora soporta VARIAS FILAS por foto (novillo + cerdo)
// La Edge Function devuelve { cliente, fecha, filas: [...] }
// ============================================================

import 'dart:convert';
import 'package:http/http.dart' as http;

class OcrResult {
  final String? clienteNombre;
  final String? fecha;
  final List<OcrFila> filas;
  final String? error;

  OcrResult({
    this.clienteNombre,
    this.fecha,
    this.filas = const [],
    this.error,
  });

  double get totalKg => filas.fold(0, (sum, f) => sum + f.totalKg);
  double get totalPesos => filas.fold(0, (sum, f) => sum + f.totalPesos);
}

class OcrFila {
  final String tipo; // "Novillo" o "Cerdo"
  final int cantMedias;
  final List<double> kgPorMedia;
  final double totalKg;
  final double precioPorKg;
  final double totalPesos;

  OcrFila({
    required this.tipo,
    required this.cantMedias,
    required this.kgPorMedia,
    required this.totalKg,
    required this.precioPorKg,
    required this.totalPesos,
  });
}

class OcrService {
  static Future<OcrResult> leerRemito({
    required String imageBase64,
    required String mediaType,
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    try {
      final functionUrl = '$supabaseUrl/functions/v1/ocr-remito';

      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $supabaseAnonKey',
        },
        body: jsonEncode({
          'image_base64': imageBase64,
          'media_type': mediaType,
        }),
      );

      if (response.statusCode != 200) {
        return OcrResult(
          error: 'Error del servidor: ${response.statusCode}. ${response.body}',
        );
      }

      final parsed = jsonDecode(response.body);

      if (parsed['error'] != null) {
        return OcrResult(error: parsed['error'] as String);
      }
      if (parsed['parse_error'] == true) {
        return OcrResult(
            error: 'No se pudo leer el remito. Intentá con otra foto.');
      }

      // Parsear el nuevo formato con filas
      final filas = <OcrFila>[];

      if (parsed['filas'] != null && parsed['filas'] is List) {
        for (final fila in parsed['filas']) {
          final kgList = <double>[];
          if (fila['kg_por_media'] != null && fila['kg_por_media'] is List) {
            for (final kg in fila['kg_por_media']) {
              if (kg != null) kgList.add((kg as num).toDouble());
            }
          }

          final totalKgFila = fila['total_kg'] != null
              ? (fila['total_kg'] as num).toDouble()
              : 0.0;
          final totalPesosFila = fila['total_pesos'] != null
              ? (fila['total_pesos'] as num).toDouble()
              : 0.0;

          // precio_por_kg viene directo del OCR, o lo calculamos
          double precioPorKg = 0;
          if (fila['precio_por_kg'] != null) {
            precioPorKg = (fila['precio_por_kg'] as num).toDouble();
          } else if (totalKgFila > 0) {
            precioPorKg = totalPesosFila / totalKgFila;
          }

          filas.add(OcrFila(
            tipo: fila['tipo'] ?? 'Novillo',
            cantMedias: fila['cant_medias'] ?? kgList.length,
            kgPorMedia: kgList,
            totalKg: totalKgFila,
            precioPorKg: precioPorKg,
            totalPesos: totalPesosFila,
          ));
        }
      } else if (parsed['kg_por_media'] != null) {
        // Formato viejo (compatibilidad): una sola fila
        final kgList = <double>[];
        for (final kg in parsed['kg_por_media']) {
          if (kg != null) kgList.add((kg as num).toDouble());
        }
        final totalKg = parsed['total_kg'] != null
            ? (parsed['total_kg'] as num).toDouble()
            : 0.0;
        final avgKg = kgList.isNotEmpty
            ? kgList.reduce((a, b) => a + b) / kgList.length
            : totalKg;

        final totalPesosOld = parsed['total_pesos'] != null
            ? (parsed['total_pesos'] as num).toDouble()
            : 0.0;

        filas.add(OcrFila(
          tipo: avgKg > 60 ? 'Novillo' : 'Cerdo',
          cantMedias: parsed['cant_medias'] ?? kgList.length,
          kgPorMedia: kgList,
          totalKg: totalKg,
          precioPorKg: totalKg > 0 ? totalPesosOld / totalKg : 0,
          totalPesos: totalPesosOld,
        ));
      }

      return OcrResult(
        clienteNombre: parsed['cliente'] as String?,
        fecha: parsed['fecha'] as String?,
        filas: filas,
      );
    } catch (e) {
      return OcrResult(error: 'Error al procesar: $e');
    }
  }
}
