// El desglose de los kg de la semana del dashboard (v19.10): a qué clientes
// fue la carne, cuántas medias y por cuánta plata.
//
// Lo que importa acá es que las sumas de la pantalla den exactamente el
// número de la tarjeta que se tocó, y que el orden sea el útil: el que más
// se llevó, primero.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';

VentaRemitoSemana _venta({
  required int numero,
  required DateTime fecha,
  required int medias,
  required double kg,
  required double importe,
  double totalFactura = 0,
  bool otrosTipos = false,
}) {
  return VentaRemitoSemana(
    remito: Remito(
      clienteId: 'c',
      fecha: fecha,
      numero: numero,
      totalPesos: totalFactura == 0 ? importe : totalFactura,
    ),
    medias: medias,
    kg: kg,
    importe: importe,
    tieneOtrosTipos: otrosTipos,
  );
}

VentaClienteSemana _cliente(
  String nombre,
  List<VentaRemitoSemana> remitos, {
  String? vendedor,
}) {
  return VentaClienteSemana(
    clienteId: nombre,
    clienteNombre: nombre,
    vendedorNombre: vendedor,
    remitos: remitos,
  );
}

void main() {
  final lunes = DateTime(2026, 10, 26);

  group('un cliente', () {
    test('suma las medias, los kg y el importe de sus remitos', () {
      final c = _cliente('LA FLORIDA', [
        _venta(
            numero: 1,
            fecha: lunes,
            medias: 2,
            kg: 180.5,
            importe: 1000000),
        _venta(
            numero: 2,
            fecha: lunes.add(const Duration(days: 2)),
            medias: 1,
            kg: 95.5,
            importe: 500000),
      ]);

      expect(c.medias, 3);
      expect(c.kg, 276.0);
      expect(c.importe, 1500000);
      expect(c.cantidadRemitos, 2);
    });

    test('los remitos quedan en orden cronológico', () {
      final c = _cliente('PERICO', [
        _venta(
            numero: 9,
            fecha: lunes.add(const Duration(days: 3)),
            medias: 1,
            kg: 90,
            importe: 100),
        _venta(numero: 4, fecha: lunes, medias: 1, kg: 90, importe: 100),
      ]);

      expect(c.remitos.map((r) => r.remito.numero), [4, 9]);
    });

    test('un remito mezclado se marca y conserva el total de la factura', () {
      final mezclado = _venta(
        numero: 7,
        fecha: lunes,
        medias: 1,
        kg: 90,
        importe: 600000,
        totalFactura: 950000,
        otrosTipos: true,
      );
      final c = _cliente('DON PEDRO', [mezclado]);

      expect(c.hayRemitosMezclados, isTrue);
      // El importe del desglose es solo la parte del tipo consultado; la
      // factura entera se muestra aparte.
      expect(c.importe, 600000);
      expect(mezclado.totalFactura, 950000);
      expect(c.totalFacturado, 950000);
    });

    test('sin tipos mezclados el importe es la factura entera', () {
      final c = _cliente('SOLO NOVILLO', [
        _venta(numero: 1, fecha: lunes, medias: 2, kg: 180, importe: 800000),
      ]);

      expect(c.hayRemitosMezclados, isFalse);
      expect(c.importe, c.totalFacturado);
    });
  });

  group('desglose de la semana', () {
    DesgloseSemanaTipo armar(List<VentaClienteSemana> clientes) =>
        DesgloseSemanaTipo(
          tipo: 'Novillo',
          semanaInicio: lunes,
          clientes: clientes,
        );

    test('los totales son la suma de los clientes', () {
      final d = armar([
        _cliente('A', [
          _venta(numero: 1, fecha: lunes, medias: 4, kg: 360, importe: 2000000)
        ]),
        _cliente('B', [
          _venta(numero: 2, fecha: lunes, medias: 2, kg: 200.5, importe: 900000)
        ]),
      ]);

      expect(d.medias, 6);
      expect(d.kg, 560.5);
      expect(d.importe, 2900000);
      expect(d.cantidadClientes, 2);
      expect(d.cantidadRemitos, 2);
      expect(d.vacio, isFalse);
    });

    test('los clientes van del que más kg se llevó al que menos', () {
      final d = armar([
        _cliente('CHICO', [
          _venta(numero: 1, fecha: lunes, medias: 1, kg: 90, importe: 100)
        ]),
        _cliente('GRANDE', [
          _venta(numero: 2, fecha: lunes, medias: 5, kg: 450, importe: 100)
        ]),
        _cliente('MEDIANO', [
          _venta(numero: 3, fecha: lunes, medias: 2, kg: 180, importe: 100)
        ]),
      ]);

      expect(d.clientes.map((c) => c.clienteNombre),
          ['GRANDE', 'MEDIANO', 'CHICO']);
    });

    test('con los mismos kg desempata alfabéticamente, sin acentos', () {
      final d = armar([
        _cliente('Zulema', [
          _venta(numero: 1, fecha: lunes, medias: 1, kg: 90, importe: 100)
        ]),
        _cliente('Ángel', [
          _venta(numero: 2, fecha: lunes, medias: 1, kg: 90, importe: 100)
        ]),
      ]);

      expect(d.clientes.map((c) => c.clienteNombre), ['Ángel', 'Zulema']);
    });

    test('una semana sin ventas queda vacía', () {
      final d = armar([]);
      expect(d.vacio, isTrue);
      expect(d.kg, 0);
      expect(d.medias, 0);
      expect(d.importe, 0);
    });

    test('la semana se guarda normalizada a la fecha, sin hora', () {
      final d = DesgloseSemanaTipo(
        tipo: 'Cerdo',
        semanaInicio: DateTime(2026, 10, 26, 13, 45),
        clientes: const [],
      );
      expect(d.semanaInicio, DateTime(2026, 10, 26));
    });
  });
}
