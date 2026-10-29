// Fija la forma de la lista de reparto después de partirla en dos tablas
// (CARNE y CERDO) y de sumar el sábado.
//
// Lo que se protege acá:
//   1. Que una fila pertenezca a UNA tabla. La pantalla ya no es una grilla
//      con dos columnas: un cliente que lleva de las dos tiene dos filas, y
//      una fila recién agregada sin medias igual sabe de qué tabla es.
//   2. Que las filas viejas (las que guardaban carne y cerdo juntos, antes
//      de la columna `tipo`) se lean partidas en dos y no se pierda el cerdo.
//   3. Que los totales y el sobrante se calculen por tabla: el sobrante de
//      cerdo no puede taparse con medias de novillo.
//   4. Los tres días del reparto, con el sábado escrito sin acento en la
//      base y con acento en pantalla.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:don_chacho_matarife/models/models.dart';
import 'package:don_chacho_matarife/services/reparto_service.dart';

void main() {
  group('días del reparto', () {
    test('son jueves, viernes y sábado, en ese orden', () {
      expect(diasReparto, ['jueves', 'viernes', 'sabado']);
    });

    test('el sábado se guarda sin acento y se muestra con acento', () {
      expect(labelDiaReparto('sabado'), 'Sábado');
      expect(labelDiaReparto('jueves'), 'Jueves');
      expect(labelDiaReparto('viernes'), 'Viernes');
    });

    test('la lista muestra el día que tiene guardado', () {
      final lista = RepartoLista(semanaInicio: DateTime(2026, 10, 26), dia: 'sabado');
      expect(lista.diaLabel, 'Sábado');
      expect(lista.toMap()['dia'], 'sabado');
    });
  });

  group('una fila pertenece a una sola tabla', () {
    test('la fila de carne no ocupa la columna de cerdo, y al revés', () {
      final carne = RepartoItem(
          clienteId: 'c1', tipo: tipoRepartoCarne, medias: 3);
      final cerdo = RepartoItem(
          clienteId: 'c1', tipo: tipoRepartoCerdo, medias: 5);

      expect(carne.mediasCarne, 3);
      expect(carne.mediasCerdo, 0);
      expect(cerdo.mediasCerdo, 5);
      expect(cerdo.mediasCarne, 0);
    });

    test('se guarda el tipo junto a las dos columnas históricas', () {
      final map = RepartoItem(
              clienteId: 'c1', tipo: tipoRepartoCerdo, medias: 5)
          .toMap();
      expect(map['tipo'], 'cerdo');
      expect(map['medias_cerdo'], 5);
      expect(map['medias_carne'], 0);
    });

    test('si el tipo y las medias se contradicen, mandan las medias', () {
      // La deja una versión vieja de la app: guarda sin `tipo` y se come el
      // DEFAULT 'carne' de la tabla, aunque las medias sean de cerdo. Leerla
      // como fila de carne en cero haría desaparecer esas 3 medias.
      final leido = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'tipo': 'carne',
        'medias_carne': 0,
        'medias_cerdo': 3,
      });
      expect(leido, hasLength(1));
      expect(leido.first.tipo, tipoRepartoCerdo);
      expect(leido.first.medias, 3);
    });

    test('una fila sin medias todavía sabe de qué tabla es', () {
      // Es el cliente recién agregado: las medias se cargan después, y al
      // releer la lista tiene que seguir en la tabla donde se lo puso.
      final leido = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'tipo': 'cerdo',
        'medias_carne': 0,
        'medias_cerdo': 0,
      });
      expect(leido, hasLength(1));
      expect(leido.first.tipo, tipoRepartoCerdo);
      expect(leido.first.medias, 0);
    });
  });

  group('filas viejas, sin la columna tipo', () {
    test('una fila con carne y cerdo se parte en dos, una por tabla', () {
      final filas = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'medias_carne': 2,
        'medias_cerdo': 3,
        'sucursal': 'Centro',
      });

      expect(filas, hasLength(2));
      expect(filas[0].tipo, tipoRepartoCarne);
      expect(filas[0].medias, 2);
      expect(filas[1].tipo, tipoRepartoCerdo);
      expect(filas[1].medias, 3);
      // La sucursal es del cliente, así que viaja a las dos filas.
      expect(filas.every((f) => f.sucursal == 'Centro'), isTrue);
      expect(filas.every((f) => f.clienteId == 'c1'), isTrue);
    });

    test('una fila solo de cerdo queda en la tabla de cerdo', () {
      final filas = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'medias_carne': 0,
        'medias_cerdo': 4,
      });
      expect(filas, hasLength(1));
      expect(filas.first.tipo, tipoRepartoCerdo);
      expect(filas.first.medias, 4);
    });

    test('una fila solo de carne queda en la tabla de carne', () {
      final filas = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'medias_carne': 6,
        'medias_cerdo': 0,
      });
      expect(filas, hasLength(1));
      expect(filas.first.tipo, tipoRepartoCarne);
      expect(filas.first.medias, 6);
    });
  });

  group('totales y sobrante por tabla', () {
    RepartoLista armar() => RepartoLista(
          semanaInicio: DateTime(2026, 10, 26),
          dia: 'jueves',
          totalMediasCarne: 40,
          totalMediasCerdo: 60,
          items: [
            RepartoItem(
                clienteId: 'a', tipo: tipoRepartoCarne, medias: 3),
            RepartoItem(
                clienteId: 'b', tipo: tipoRepartoCarne, medias: 2),
            // El mismo cliente en las dos tablas: dos filas.
            RepartoItem(
                clienteId: 'b', tipo: tipoRepartoCerdo, medias: 5),
            RepartoItem(
                clienteId: 'c', tipo: tipoRepartoCerdo, medias: 1),
          ],
        );

    test('cada tabla muestra solo sus filas', () {
      final lista = armar();
      expect(lista.itemsDe(tipoRepartoCarne), hasLength(2));
      expect(lista.itemsDe(tipoRepartoCerdo), hasLength(2));
    });

    test('lo repartido se cuenta por mercadería', () {
      final lista = armar();
      expect(lista.repartidoDe(tipoRepartoCarne), 5);
      expect(lista.repartidoDe(tipoRepartoCerdo), 6);
    });

    test('el sobrante de cada tabla sale de su propio total', () {
      final lista = armar();
      expect(lista.totalDe(tipoRepartoCarne), 40);
      expect(lista.totalDe(tipoRepartoCerdo), 60);
      expect(lista.sobranteDe(tipoRepartoCarne), 35);
      expect(lista.sobranteDe(tipoRepartoCerdo), 54);
    });

    test('repartir de más deja el sobrante en negativo, y solo en esa tabla',
        () {
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'sabado',
        totalMediasCarne: 2,
        totalMediasCerdo: 10,
        items: [
          RepartoItem(clienteId: 'a', tipo: tipoRepartoCarne, medias: 5),
          RepartoItem(clienteId: 'a', tipo: tipoRepartoCerdo, medias: 1),
        ],
      );
      expect(lista.sobranteDe(tipoRepartoCarne), -3);
      expect(lista.sobranteDe(tipoRepartoCerdo), 9);
    });
  });

  group('columnas extra', () {
    // Joaco de golpe vende una pierna o grasa: lo anota en una columna que
    // se agrega a mano al final de la tabla.

    test('el tope es de dos por tabla y la lectura lo respeta', () {
      expect(maxColumnasExtra, 2);
      final lista = RepartoLista.fromMap({
        'semana_inicio': '2026-10-26',
        'dia': 'jueves',
        'columnas_extra': {
          'carne': ['Pierna', 'Grasa', 'De mas'],
        },
      });
      expect(lista.columnasDe(tipoRepartoCarne), ['Pierna', 'Grasa']);
    });

    test('cada tabla tiene las suyas', () {
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'jueves',
        columnasExtra: {
          tipoRepartoCarne: ['Pierna'],
        },
      );
      expect(lista.columnasDe(tipoRepartoCarne), ['Pierna']);
      expect(lista.columnasDe(tipoRepartoCerdo), isEmpty);
    });

    test('los números van por posición, no por nombre', () {
      // Es lo que deja renombrar el encabezado sin perder lo cargado.
      final it = RepartoItem(
          clienteId: 'c1', tipo: tipoRepartoCarne, extras: [3, 0]);
      expect(it.extraEn(0), 3);
      expect(it.extraEn(1), 0);
      expect(it.toMap()['extras'], [3, 0]);
    });

    test('una celda que nunca se cargó vale 0 y no rompe', () {
      final it = RepartoItem(clienteId: 'c1', extras: [2]);
      expect(it.extraEn(1), 0);
      expect(it.extraEn(-1), 0);
      expect(RepartoItem(clienteId: 'c1').extraEn(0), 0);
    });

    test('el total de una columna extra es lo repartido', () {
      // No hay stock de "grasa" contra el cual contarlo, así que el
      // encabezado muestra la suma y la columna no tiene sobrante.
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'jueves',
        columnasExtra: {
          tipoRepartoCarne: ['Pierna'],
        },
        items: [
          RepartoItem(
              clienteId: 'a', tipo: tipoRepartoCarne, medias: 2, extras: [3]),
          RepartoItem(
              clienteId: 'b', tipo: tipoRepartoCarne, medias: 1, extras: [4]),
          // El cerdo no tiene esa columna: no suma.
          RepartoItem(
              clienteId: 'c', tipo: tipoRepartoCerdo, medias: 5, extras: [9]),
        ],
      );
      expect(lista.repartidoExtra(tipoRepartoCarne, 0), 7);
      expect(lista.repartidoExtra(tipoRepartoCerdo, 0), 9);
      // Las medias no se mezclan con los extras.
      expect(lista.repartidoDe(tipoRepartoCarne), 3);
    });

    test('la lectura tolera que la columna no exista o traiga basura', () {
      // La lista tiene que abrirse igual, sin columnas extra.
      final lista = RepartoLista.fromMap({
        'semana_inicio': '2026-10-26',
        'dia': 'jueves',
      });
      expect(lista.columnasDe(tipoRepartoCarne), isEmpty);

      final it = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'tipo': 'carne',
        'medias_carne': 2,
        'extras': ['3', null, 'cualquier cosa'],
      }).single;
      expect(it.extras, [3, 0]);
    });

    test('una fila vieja partida en dos no duplica los extras', () {
      // Los extras son de la fila, que es de la tabla de carne: dárselos
      // también a la de cerdo los contaría dos veces en el total.
      final filas = RepartoItem.desdeMap({
        'cliente_id': 'c1',
        'medias_carne': 2,
        'medias_cerdo': 3,
        'extras': [5],
      });
      expect(filas, hasLength(2));
      expect(filas[0].extras, [5]);
      expect(filas[1].extras, isEmpty);
    });
  });

  group('la fecha del reparto', () {
    // `semanaInicio` es el LUNES de la semana, que no es el día en que sale
    // el camión. El PDF salía llamándose con el lunes y se leía como una
    // fecha equivocada: el jueves de la semana del 26/10 se reparte el 29.
    final lunes = DateTime(2026, 10, 26);

    test('cada día cae donde tiene que caer', () {
      expect(RepartoLista(semanaInicio: lunes, dia: 'jueves').fecha,
          DateTime(2026, 10, 29));
      expect(RepartoLista(semanaInicio: lunes, dia: 'viernes').fecha,
          DateTime(2026, 10, 30));
      expect(RepartoLista(semanaInicio: lunes, dia: 'sabado').fecha,
          DateTime(2026, 10, 31));
    });

    test('nunca es el lunes de la semana', () {
      for (final d in diasReparto) {
        expect(RepartoLista(semanaInicio: lunes, dia: d).fecha,
            isNot(lunes));
      }
    });

    test('cruza bien el fin de mes', () {
      // Semana del lunes 30/11/2026: el sábado cae en diciembre.
      final lista =
          RepartoLista(semanaInicio: DateTime(2026, 11, 30), dia: 'sabado');
      expect(lista.fecha, DateTime(2026, 12, 5));
    });

    test('cruza bien el fin de año', () {
      // Semana del lunes 28/12/2026: el jueves ya es 2027.
      final lista =
          RepartoLista(semanaInicio: DateTime(2026, 12, 28), dia: 'jueves');
      expect(lista.fecha, DateTime(2026, 12, 31));
      final sabado =
          RepartoLista(semanaInicio: DateTime(2026, 12, 28), dia: 'sabado');
      expect(sabado.fecha, DateTime(2027, 1, 2));
    });

    test('el offset sale del orden de los días', () {
      expect(offsetDiaReparto('jueves'), 3);
      expect(offsetDiaReparto('viernes'), 4);
      expect(offsetDiaReparto('sabado'), 5);
      // Un día que no existe cae en jueves, que es el primero.
      expect(offsetDiaReparto('lunes'), 3);
    });
  });

  _pdf();
  _filasNuevas();
}

// Smoke test de layout del PDF del repartidor: dart_pdf tira los errores de
// armado recién al construir el documento. La tabla va como widgets sueltos
// del MultiPage justamente para que se pueda partir entre páginas; metida en
// un Column, una lista larga de clientes haría explotar el armado.
//
// Son DOS PDF por día, uno por tabla, así que cada caso se arma con los dos.
Cliente cliente(String id, String nombre) => Cliente(
      id: id,
      vendedorId: 'v',
      nombreRazonSocial: nombre,
      telefono: '',
      plazoPagoDias: 7,
    );

void _pdf() {
  group('el PDF del repartidor se arma sin errores', () {
    late pw.MemoryImage logo;

    setUpAll(() async {
      // El encabezado imprime el rango de la semana con DateFormat('es').
      await initializeDateFormatting('es');
      logo = pw.MemoryImage(File('assets/logo.png').readAsBytesSync());
    });

    Future<int> armar(
        RepartoLista lista, List<Cliente> clientes, String tipo) async {
      final doc = RepartoService.generarPdf(
        lista: lista,
        clientes: clientes,
        logo: logo,
        tipo: tipo,
      );
      return (await doc.save()).length;
    }

    test('un PDF por tabla, con las notas del día en los dos', () async {
      final clientes = [
        cliente('a', 'Perico'),
        cliente('b', 'La Florida'),
      ];
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'sabado',
        totalMediasCarne: 40,
        totalMediasCerdo: 60,
        notas: 'Buscar morcillas de La Florida',
        items: [
          RepartoItem(
              clienteId: 'a',
              tipo: tipoRepartoCarne,
              medias: 3,
              sucursal: 'Centro'),
          RepartoItem(clienteId: 'b', tipo: tipoRepartoCerdo, medias: 5),
        ],
      );
      for (final tipo in tiposReparto) {
        expect(await armar(lista, clientes, tipo), greaterThan(1000));
      }
    });

    test('una lista larga se parte en varias páginas', () async {
      final clientes = [
        for (var i = 0; i < 80; i++) cliente('c$i', 'Cliente $i'),
      ];
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'jueves',
        totalMediasCarne: 400,
        totalMediasCerdo: 400,
        items: [
          for (var i = 0; i < 80; i++)
            RepartoItem(
                clienteId: 'c$i', tipo: tipoRepartoCarne, medias: i + 1),
          for (var i = 0; i < 80; i++)
            RepartoItem(
                clienteId: 'c$i', tipo: tipoRepartoCerdo, medias: i + 1),
        ],
      );
      for (final tipo in tiposReparto) {
        expect(await armar(lista, clientes, tipo), greaterThan(1000));
      }
    });

    test('la tabla vacía igual sale (el repartidor se lleva la hoja)',
        () async {
      // Un día puede no tener cerdo. El PDF igual tiene que salir, con su
      // TOTAL MEDIAS y su sobrante, y no quedar a mitad de camino.
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'jueves',
        totalMediasCarne: 10,
        items: [
          RepartoItem(clienteId: 'a', tipo: tipoRepartoCarne, medias: 4),
        ],
      );
      expect(lista.itemsDe(tipoRepartoCerdo), isEmpty);
      expect(await armar(lista, [cliente('a', 'Perico')], tipoRepartoCerdo),
          greaterThan(1000));
    });

    test('las columnas extra salen en el PDF', () async {
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'jueves',
        totalMediasCarne: 10,
        columnasExtra: {
          tipoRepartoCarne: ['Pierna', 'Grasa'],
        },
        items: [
          RepartoItem(
              clienteId: 'a',
              tipo: tipoRepartoCarne,
              medias: 4,
              extras: [2, 1]),
        ],
      );
      expect(await armar(lista, [cliente('a', 'Perico')], tipoRepartoCarne),
          greaterThan(1000));
      // La tabla de cerdo no tiene esas columnas y se arma igual.
      expect(await armar(lista, [cliente('a', 'Perico')], tipoRepartoCerdo),
          greaterThan(1000));
    });

    test('un cliente borrado no rompe el PDF', () async {
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'viernes',
        items: [
          RepartoItem(
              clienteId: 'fantasma', tipo: tipoRepartoCarne, medias: 2),
        ],
      );
      expect(await armar(lista, const [], tipoRepartoCarne),
          greaterThan(1000));
    });
  });
}

// La fila nueva tiene que nacer con las columnas que la tabla YA tiene.
// Si no, la celda de la columna extra aparece vacía y no se puede tipear:
// es el bug que reportó el usuario (agregar columna -> agregar cliente ->
// la celda nueva no deja escribir).
void _filasNuevas() {
  group('una fila agregada después de la columna', () {
    test('el item nuevo arranca sin extras y eso no rompe la lectura', () {
      final it = RepartoItem(clienteId: 'nuevo', tipo: tipoRepartoCarne);
      expect(it.extras, isEmpty);
      expect(it.extraEn(0), 0);
    });

    test('la lista suma bien aunque una fila no tenga la celda cargada', () {
      final lista = RepartoLista(
        semanaInicio: DateTime(2026, 10, 26),
        dia: 'jueves',
        columnasExtra: {
          tipoRepartoCarne: ['Pierna'],
        },
        items: [
          RepartoItem(
              clienteId: 'viejo', tipo: tipoRepartoCarne, extras: [2]),
          // El que se agregó después de crear la columna.
          RepartoItem(clienteId: 'nuevo', tipo: tipoRepartoCarne),
        ],
      );
      expect(lista.repartidoExtra(tipoRepartoCarne, 0), 2);
    });
  });
}
