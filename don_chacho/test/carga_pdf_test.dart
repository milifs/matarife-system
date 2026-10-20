// Fija la regla del PDF de cargas: el bloque de DIFERENCIA DE RINDE solo se
// imprime cuando el proveedor rindió de MENOS que el rinde asegurado.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:don_chacho_matarife/models/models.dart';
import 'package:don_chacho_matarife/services/carga_pdf_service.dart';

Carga carga({double? kgMediaRes, double rindeAsegurado = 58}) => Carga(
      fecha: DateTime(2026, 10, 16),
      proveedorId: 'p1',
      cantidadAnimales: 25,
      kgVivo: 9807,
      desvastePorcentaje: 5,
      precioKgVivo: 5400,
      rindeAsegurado: rindeAsegurado,
      kgMediaRes: kgMediaRes,
    );

void main() {
  // kg neto = 9807 * 0,95 = 9.316,65 -> esperados al 58% = 5.403,657 -> 5.404

  test('rindió de menos: el bloque VA', () {
    final c = carga(kgMediaRes: 5375);
    expect(c.diferenciaRindeKg, greaterThan(0));
    expect(CargaPdfService.debeImprimirRinde(c), isTrue);
  });

  test('rindió de más: el bloque NO va', () {
    final c = carga(kgMediaRes: 5600);
    expect(c.diferenciaRindeKg, lessThan(0));
    expect(CargaPdfService.debeImprimirRinde(c), isFalse);
  });

  test('rindió exacto: el bloque NO va', () {
    final c = carga(kgMediaRes: 5404);
    expect(c.diferenciaRindeKg, 0);
    expect(CargaPdfService.debeImprimirRinde(c), isFalse);
  });

  test('todavia sin faenar: el bloque NO va', () {
    final c = carga();
    expect(c.tieneFaena, isFalse);
    expect(CargaPdfService.debeImprimirRinde(c), isFalse);
  });

  test('diferencia menor a medio kilo redondea a 0 y el bloque NO va', () {
    // esperados 5.404 vs obtenidos 5.403,6 -> 0,4 kg -> redondea a 0
    final c = carga(kgMediaRes: 5403.6);
    expect(c.diferenciaRindeKg, 0);
    expect(CargaPdfService.debeImprimirRinde(c), isFalse);
  });

  // Smoke test de layout: si una fila se pasa del ancho o un widget no entra,
  // pdf lo tira recien al armar el documento. Mejor que explote aca.
  group('el documento se arma sin errores', () {
    late pw.MemoryImage logo;

    setUpAll(() {
      logo = pw.MemoryImage(File('assets/logo.png').readAsBytesSync());
    });

    Future<int> armar(Carga c, {List<CargaPago> pagos = const []}) async {
      final doc = CargaPdfService.generarPdf(
        carga: c,
        nombreProveedor: 'Bily Sayus',
        pagos: pagos,
        saldoAnterior: 0,
        pagado: pagos.fold(0.0, (t, p) => t + p.monto),
        saldoFinal: -1000,
        logo: logo,
      );
      final bytes = await doc.save();
      return bytes.length;
    }

    CargaPago pago(double monto, String medio) => CargaPago(
          cargaId: 'c1',
          fecha: DateTime(2026, 10, 16),
          medio: medio,
          monto: monto,
        );

    test('con faena, pagos y rinde negativo', () async {
      final bytes = await armar(
        carga(kgMediaRes: 5375),
        pagos: [
          pago(1100000, 'transferencia'),
          pago(1200000, 'efectivo'),
          pago(7000000, 'cheque'),
        ],
      );
      expect(bytes, greaterThan(1000));
    });

    test('sin faena y sin pagos', () async {
      expect(await armar(carga()), greaterThan(1000));
    });

    test('muchos pagos (se parte en varias paginas)', () async {
      final muchos =
          List.generate(60, (i) => pago(1000000 + i * 1.0, 'cheque'));
      expect(await armar(carga(kgMediaRes: 5375), pagos: muchos),
          greaterThan(1000));
    });

    // La lista de pagos se corta a mano en tarjetas de 18 porque las tarjetas
    // no se parten solas: si una pasara el alto de la hoja, pdf tira excepcion
    // en vez de maquetar. Estos casos cruzan los bordes del corte.
    for (final n in [17, 18, 19, 36, 37, 200]) {
      test('$n pagos no rompen el armado', () async {
        final lista =
            List.generate(n, (i) => pago(1000000 + i * 1.0, 'cheque'));
        expect(await armar(carga(kgMediaRes: 5375), pagos: lista),
            greaterThan(1000));
      });
    }
  });
}
