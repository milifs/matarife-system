// Fija la aritmética del cierre de jornada del cobrador: el total del día, el
// desglose por medio de pago y, sobre todo, el EFECTIVO, que es la plata que
// el cobrador trae encima y tiene que rendir.
//
// Lo que se protege acá es que el cierre sea BRUTO: una transferencia de
// $1.000.000 entra como $1.000.000 aunque internamente se le descuente el
// 6,2%. El cierre es una rendición de plata cobrada, no un cálculo de
// ganancia.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';

void main() {
  // Un cobro con los medios que se le pasen.
  CobroJornada cobro({
    required String cliente,
    required Map<MedioPago, double> medios,
    DateTime? fecha,
    DateTime? creadoEn,
    String clienteId = 'c1',
  }) {
    final dia = fecha ?? DateTime(2026, 10, 23);
    final pago = Pago(
      id: 'p-$cliente-${medios.values.join()}',
      clienteId: clienteId,
      fecha: dia,
      numero: 1,
      montoTotal: medios.values.fold(0, (s, m) => s + m),
      netoRecibido: 0,
      creadoEn: creadoEn ?? DateTime(2026, 10, 23, 10, 30),
    );
    return CobroJornada(
      pago: pago,
      clienteNombre: cliente,
      medios: [
        for (final e in medios.entries)
          PagoMedio(pagoId: pago.id, medio: e.key, monto: e.value),
      ],
    );
  }

  ResumenJornada jornada(List<CobroJornada> cobros) => ResumenJornada(
        cobrador: 'Arturo Aguilera',
        dia: DateTime(2026, 10, 23),
        cobros: cobros,
      );

  test('una jornada sin cobros queda vacía y en cero', () {
    final j = jornada([]);
    expect(j.vacia, isTrue);
    expect(j.total, 0);
    expect(j.efectivo, 0);
    expect(j.cantidadPagos, 0);
    expect(j.cantidadClientes, 0);
  });

  test('suma el total y lo separa por medio de pago', () {
    final j = jornada([
      cobro(cliente: 'PERICO', medios: {MedioPago.efectivo: 500000}),
      cobro(
        cliente: 'LA FLORIDA',
        clienteId: 'c2',
        medios: {MedioPago.transferencia: 1000000},
      ),
      cobro(
        cliente: 'DON JUAN',
        clienteId: 'c3',
        medios: {MedioPago.cheque: 250000},
      ),
    ]);

    expect(j.total, 1750000);
    expect(j.efectivo, 500000);
    expect(j.transferencia, 1000000);
    expect(j.cheque, 250000);
    expect(j.cantidadPagos, 3);
    expect(j.cantidadClientes, 3);
  });

  test('la transferencia entra bruta, sin el descuento interno del 6,2%', () {
    final j = jornada([
      cobro(
        cliente: 'LA FLORIDA',
        medios: {MedioPago.transferencia: 1000000},
      ),
    ]);

    // El PagoMedio sí calcula el neto (937.000), pero el cierre no lo usa.
    expect(j.total, 1000000);
    expect(j.transferencia, 1000000);
  });

  test('un pago con dos medios reparte cada parte a su balde', () {
    final j = jornada([
      cobro(cliente: 'PERICO', medios: {
        MedioPago.efectivo: 300000,
        MedioPago.transferencia: 700000,
      }),
    ]);

    expect(j.total, 1000000);
    expect(j.efectivo, 300000);
    expect(j.transferencia, 700000);
    expect(j.desgloseCompleto, isTrue);
  });

  test('dos cobros al mismo cliente cuentan como un cliente', () {
    final j = jornada([
      cobro(cliente: 'PERICO', medios: {MedioPago.efectivo: 100000}),
      cobro(cliente: 'PERICO', medios: {MedioPago.efectivo: 200000}),
    ]);

    expect(j.cantidadPagos, 2);
    expect(j.cantidadClientes, 1);
    expect(j.efectivo, 300000);
  });

  test('los cobros salen ordenados por hora de carga', () {
    final tarde = cobro(
      cliente: 'TARDE',
      medios: {MedioPago.efectivo: 1},
      creadoEn: DateTime(2026, 10, 23, 18, 5),
    );
    final manana = cobro(
      cliente: 'MAÑANA',
      medios: {MedioPago.efectivo: 2},
      creadoEn: DateTime(2026, 10, 23, 8, 40),
    );

    final j = jornada([tarde, manana]);

    expect(j.cobros.map((c) => c.clienteNombre), ['MAÑANA', 'TARDE']);
    expect(j.cobros.first.hora, '08:40');
    expect(j.cobros.last.hora, '18:05');
  });

  group('desglose incompleto', () {
    test('un pago sin medios cargados no se inventa como efectivo', () {
      final pago = Pago(
        clienteId: 'c1',
        fecha: DateTime(2026, 10, 23),
        montoTotal: 400000,
        netoRecibido: 400000,
      );
      final j = jornada([
        CobroJornada(pago: pago, clienteNombre: 'SIN MEDIOS'),
        cobro(cliente: 'PERICO', medios: {MedioPago.efectivo: 100000}),
      ]);

      expect(j.total, 500000);
      expect(j.efectivo, 100000, reason: 'solo el que sí tiene medio');
      expect(j.sinDesglosar, 400000);
      expect(j.desgloseCompleto, isFalse);
    });

    test('cuando todo tiene medio, no queda resto', () {
      final j = jornada([
        cobro(cliente: 'PERICO', medios: {MedioPago.efectivo: 100000}),
      ]);
      expect(j.sinDesglosar, 0);
      expect(j.desgloseCompleto, isTrue);
    });
  });

  group('cargadoOtroDia', () {
    test('cobro del día cargado el mismo día', () {
      final c = cobro(
        cliente: 'PERICO',
        medios: {MedioPago.efectivo: 1},
        fecha: DateTime(2026, 10, 23),
        creadoEn: DateTime(2026, 10, 23, 19, 0),
      );
      expect(c.cargadoOtroDia, isFalse);
    });

    test('cobro del día cargado al otro día queda marcado', () {
      final c = cobro(
        cliente: 'PERICO',
        medios: {MedioPago.efectivo: 1},
        fecha: DateTime(2026, 10, 23),
        creadoEn: DateTime(2026, 10, 24, 9, 15),
      );
      expect(c.cargadoOtroDia, isTrue);
    });
  });

  test('el día del resumen se normaliza a medianoche', () {
    final j = ResumenJornada(
      cobrador: 'Arturo Aguilera',
      dia: DateTime(2026, 10, 23, 17, 42),
      cobros: const [],
    );
    expect(j.dia, DateTime(2026, 10, 23));
  });

  test('la etiqueta de medios junta los dos medios de un pago', () {
    final c = cobro(cliente: 'PERICO', medios: {
      MedioPago.efectivo: 1,
      MedioPago.cheque: 2,
    });
    expect(c.mediosLabel, 'Efectivo + Cheque');
  });
}
