// Fija la aritmética del depósito, que es todo el valor del módulo: existe
// porque sacaron dos medias de la cámara, nadie cargó el remito y no se pudo
// saber dónde estaban.
//
// Lo que se protege acá:
//   1. La tabla de equivalencias. El campo del remito se llama "Medias" pero
//      cuenta unidades del CORTE elegido: 3 piernas son 1 media, no 3. La
//      media de novillo se parte en tres (pierna + octavo + plancha de asado)
//      y el "1/4 delantero" son dos de esos tercios.
//   2. Que los tercios cierren EXACTO. Con 0,33 en vez de la fracción, tres
//      cortes darían 0,99 y el sistema inventaría un faltante fantasma.
//   3. Los dos stocks separados: una media de cerdo no puede tapar un
//      faltante de novillo.
//   4. El veredicto: faltan / sobran / dan redondos, con su tolerancia.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';
import 'package:don_chacho_matarife/utils/formatters.dart';

void main() {
  group('tabla de equivalencias', () {
    test('una media entera vale 1, sea novillo o cerdo', () {
      expect(equivalenciaEnMedias('Novillo'), 1);
      expect(equivalenciaEnMedias('Cerdo'), 1);
    });

    test('los tres cortes de la media valen un tercio cada uno', () {
      expect(equivalenciaEnMedias('Pierna mocha'), closeTo(1 / 3, 1e-12));
      expect(equivalenciaEnMedias('Pierna pistola'), closeTo(1 / 3, 1e-12));
      expect(equivalenciaEnMedias('Plancha de asado'), closeTo(1 / 3, 1e-12));
      expect(equivalenciaEnMedias('Octavo'), closeTo(1 / 3, 1e-12));
    });

    test('el 1/4 delantero son dos tercios (octavo + plancha de asado)', () {
      expect(equivalenciaEnMedias('1/4 delantero'), closeTo(2 / 3, 1e-12));
      expect(
        equivalenciaEnMedias('1/4 delantero'),
        closeTo(
          equivalenciaEnMedias('Octavo') +
              equivalenciaEnMedias('Plancha de asado'),
          1e-12,
        ),
      );
    });

    test('pierna + octavo + plancha de asado dan una media justa', () {
      // La razón de usar la fracción exacta y no 0,33: con 0,33 esto daría
      // 0,99 y cada media despostada inventaría 0,01 de faltante.
      final total = equivalenciaEnMedias('Pierna mocha') +
          equivalenciaEnMedias('Octavo') +
          equivalenciaEnMedias('Plancha de asado');
      expect(total, closeTo(1, toleranciaMedias));
    });

    test('es tolerante a mayúsculas y espacios de más', () {
      expect(equivalenciaEnMedias('  octavo '), closeTo(1 / 3, 1e-12));
      expect(equivalenciaEnMedias('NOVILLO'), 1);
    });

    test('un tipo desconocido cuenta como una media entera', () {
      // Criterio conservador y el que dice el campo del formulario. No se
      // usa en la práctica: el stock arranca en la fecha configurada y los
      // tipos salen de un dropdown fijo desde v18.17.
      expect(equivalenciaEnMedias('media res'), 1);
      expect(equivalenciaEnMedias(''), 1);
    });

    test('todo el catálogo de tipos de carne tiene equivalencia', () {
      // El catálogo del dropdown de remito y de nota de pedido.
      const catalogo = [
        'Novillo',
        'Cerdo',
        'Pierna mocha',
        'Pierna pistola',
        'Plancha de asado',
        'Octavo',
        '1/4 delantero',
      ];
      for (final tipo in catalogo) {
        expect(equivalenciasMedia.containsKey(tipo), isTrue,
            reason: 'falta $tipo en la tabla de equivalencias');
      }
      expect(equivalenciasMedia.length, catalogo.length);
    });
  });

  group('a qué stock le pega cada tipo', () {
    test('solo Cerdo es cerdo', () {
      expect(stockDeTipoCarne('Cerdo'), Proveedor.tipoCerdo);
      expect(stockDeTipoCarne('cerdo'), Proveedor.tipoCerdo);
    });

    test('novillo y sus cinco cortes son novillo', () {
      for (final tipo in [
        'Novillo',
        'Pierna mocha',
        'Pierna pistola',
        'Plancha de asado',
        'Octavo',
        '1/4 delantero',
      ]) {
        expect(stockDeTipoCarne(tipo), Proveedor.tipoNovillo,
            reason: '$tipo debería descontar del stock de novillo');
      }
    });
  });

  group('animales a medias', () {
    test('cada animal en pie son dos medias', () {
      expect(mediasPorAnimal, 2);
      // El caso del circuito: se compran 100 vacas, existen 200 medias.
      expect(100 * mediasPorAnimal, 200);
    });
  });

  group('la ecuación del stock', () {
    test('el teórico suma entradas y resta todo lo que salió', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        compradas: 200,
        entradas: 1,
        remitidas: 180,
        salidasPendientes: 2,
        salidasDefinitivas: 1,
      );
      // 10 + 200 + 1 - 180 - 2 - 1
      expect(stock.teorico, 28);
    });

    test('una compra nueva se suma a lo que quedó sin vender', () {
      // "Cuando se hace una nueva compra se le debe sumar al total la
      // cantidad de medias que hay en depósito."
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 15,
        compradas: 200,
      );
      expect(stock.totalDisponible, 215);
      expect(stock.teorico, 215);
    });

    test('sin recuento no hay con qué comparar', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 20,
      );
      expect(stock.tieneRecuento, isFalse);
      expect(stock.diferencia, isNull);
      expect(stock.cierra, isFalse);
      expect(stock.faltan, isFalse);
      expect(stock.sobran, isFalse);
    });
  });

  group('el veredicto', () {
    // El caso que motivó el módulo: el sistema cuenta 20 y en la cámara hay
    // 15, así que 5 medias salieron sin que nadie cargara el remito.
    test('faltan medias cuando el recuento es menor que el teórico', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        compradas: 200,
        remitidas: 180,
        recuento: 15,
        teoricoAlRecuento: 20,
      );
      expect(stock.faltan, isTrue);
      expect(stock.sobran, isFalse);
      expect(stock.cierra, isFalse);
      expect(stock.faltantes, 5);
      expect(stock.sobrantes, 0);
    });

    test('sobran medias cuando el recuento es mayor que el teórico', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        recuento: 12,
        teoricoAlRecuento: 10,
      );
      expect(stock.sobran, isTrue);
      expect(stock.faltan, isFalse);
      expect(stock.sobrantes, 2);
      expect(stock.faltantes, 0);
    });

    test('los números dan redondos cuando coinciden', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        recuento: 8,
        teoricoAlRecuento: 8,
      );
      expect(stock.cierra, isTrue);
      expect(stock.faltan, isFalse);
      expect(stock.sobran, isFalse);
      expect(stock.diferencia, 0);
    });

    test('un resto de coma flotante no enciende la alerta', () {
      // Tres cortes de un tercio sumados dan 0,99999...: sin tolerancia el
      // sistema gritaría por una diezmilésima de media.
      final teorico = 10 - (1 / 3 + 1 / 3 + 1 / 3);
      final stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        recuento: 9,
        teoricoAlRecuento: teorico,
      );
      expect(stock.cierra, isTrue, reason: 'teórico fue $teorico');
    });

    test('media media de diferencia sí enciende la alerta', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        recuento: 9.5,
        teoricoAlRecuento: 10,
      );
      expect(stock.cierra, isFalse);
      expect(stock.faltan, isTrue);
      expect(stock.faltantes, closeTo(0.5, 1e-12));
    });
  });

  group('el circuito completo de Rocío', () {
    // "En Depósito quedaron 10 medias. Rocío presiona Salida > 2 medias >
    // deben quedar 8 en depósito. Pero todavía está pendiente la carga de ese
    // remito por esas 2 medias. Una vez que se registre ese remito ya dan los
    // números redondos."
    test('la salida sin remito deja 8 en la cámara y queda avisando', () {
      final salida = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
      );
      final stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        salidasPendientes: 2,
        pendientes: [salida],
        recuento: 8,
        teoricoAlRecuento: 8,
      );
      expect(stock.teorico, 8);
      expect(stock.cierra, isTrue, reason: 'la salida ya explica las 2');
      expect(stock.hayPendientes, isTrue,
          reason: 'pero el remito todavía falta');
      expect(salida.esSalidaPendienteDeRemito, isTrue);
      expect(salida.esSalidaDefinitiva, isFalse);
    });

    test('cargado el remito, la salida se cierra y el total no se duplica',
        () {
      // La salida deja de descontar (ya descuenta el remito), así que las 2
      // medias se cuentan una sola vez: 10 - 2 = 8, no 6.
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        remitidas: 2,
        salidasPendientes: 0,
        recuento: 8,
        teoricoAlRecuento: 8,
      );
      expect(stock.teorico, 8);
      expect(stock.hayPendientes, isFalse);
      expect(stock.cierra, isTrue);
    });

    test('una salida definitiva descuenta para siempre', () {
      final merma = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 1,
        esperaRemito: false,
      );
      expect(merma.esSalidaDefinitiva, isTrue);
      expect(merma.esSalidaPendienteDeRemito, isFalse);
    });
  });

  group('DepositoMovimiento', () {
    test('el número se formatea D-0001 y no se manda si no existe', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 3,
      );
      expect(mov.numero, 0);
      expect(mov.toMap().containsKey('numero'), isFalse,
          reason: 'lo asigna la secuencia de Postgres');

      mov.numero = 7;
      expect(mov.numeroFormateado, 'D-0007');
      expect(mov.toMap()['numero'], 7);
    });

    test('las etiquetas de clase y tipo', () {
      expect(
        DepositoMovimiento(clase: DepositoMovimiento.claseEntrada).claseLabel,
        'Entrada',
      );
      expect(
        DepositoMovimiento(clase: DepositoMovimiento.claseSalida).claseLabel,
        'Salida',
      );
      expect(
        DepositoMovimiento(clase: DepositoMovimiento.claseRecuento).claseLabel,
        'Recuento',
      );
      expect(
        DepositoMovimiento(
          clase: DepositoMovimiento.claseEntrada,
          tipo: Proveedor.tipoCerdo,
        ).tipoLabel,
        'Cerdo',
      );
    });

    test('fromMap cae en novillo si el tipo viene raro', () {
      final mov = DepositoMovimiento.fromMap({
        'id': 'm1',
        'clase': 'entrada',
        'medias': 2,
        'tipo': null,
      });
      expect(mov.tipo, Proveedor.tipoNovillo);
      expect(mov.medias, 2);
    });

    test('la baja arrastra el motivo y los datos del movimiento', () {
      final mov = DepositoMovimiento(
        numero: 4,
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        observacion: 'se la llevó el flete',
      );
      final baja = DepositoMovimientoEliminado.desde(
        mov,
        observacion: 'cargada dos veces',
        eliminadoPor: 'Rocío',
      );
      expect(baja.movimientoId, mov.id);
      expect(baja.movimientoNumero, 4);
      expect(baja.medias, 2);
      expect(baja.observacionOriginal, 'se la llevó el flete');
      expect(baja.observacion, 'cargada dos veces');
      expect(baja.eliminadoPor, 'Rocío');
    });
  });

  group('kg por media (v19.6)', () {
    // Los kilos son INFORMATIVOS: la ecuación cierra por medias. Y son
    // OPCIONALES, porque un campo obligatorio que frena a la cajera sin
    // balanza a mano reabre el agujero que el módulo vino a tapar.

    test('el total es la suma de los kg cargados', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        kgsPorMedia: [118.5, 121],
      );
      expect(mov.totalKg, closeTo(239.5, 1e-9));
      expect(mov.tieneKg, isTrue);
      expect(mov.mediasSinPesar, 0);
    });

    test('un movimiento sin pesar no rompe nada', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
      );
      expect(mov.kgsPorMedia, isEmpty);
      expect(mov.totalKg, 0);
      expect(mov.tieneKg, isFalse);
      expect(mov.mediasSinPesar, 2);
    });

    test('avisa cuántas medias quedaron sin pesar', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseRecuento,
        medias: 5,
        kgsPorMedia: [120, 118],
      );
      expect(mov.mediasSinPesar, 3);
    });

    test('con un corte, la media fraccionada cuenta como una a pesar', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 1 / 3,
      );
      expect(mov.mediasSinPesar, 1);
    });

    test('pesar de más no da negativo', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 1,
        kgsPorMedia: [120, 118],
      );
      expect(mov.mediasSinPesar, 0);
    });

    test('los kg viajan al toMap como lista', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 2,
        kgsPorMedia: [100, 110],
      );
      expect(mov.toMap()['kgs_por_media'], [100, 110]);
    });

    test('fromMap tolera que la columna no exista todavía', () {
      // La columna se agregó en v19.6, con el módulo ya en producción.
      final mov = DepositoMovimiento.fromMap({
        'id': 'm1',
        'clase': 'salida',
        'medias': 2,
      });
      expect(mov.kgsPorMedia, isEmpty);
      expect(mov.totalKg, 0);
    });

    test('fromMap descarta basura en vez de romper la pantalla', () {
      final mov = DepositoMovimiento.fromMap({
        'id': 'm1',
        'clase': 'salida',
        'medias': 3,
        'kgs_por_media': [120, 'ochenta', null, 95],
      });
      expect(mov.kgsPorMedia, [120, 95]);
      expect(mov.totalKg, 215);
    });

    test('la baja se lleva los kg para poder reconstruir el movimiento', () {
      final mov = DepositoMovimiento(
        numero: 3,
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        kgsPorMedia: [118, 121],
      );
      final baja = DepositoMovimientoEliminado.desde(
        mov,
        observacion: 'cargada dos veces',
      );
      expect(baja.kgsPorMedia, [118, 121]);
      expect(baja.toMap()['kgs_por_media'], [118, 121]);
    });

    test('los kg NO entran en la ecuación: el veredicto es por medias', () {
      // Mismo stock, un recuento con kg y otro sin: el veredicto no cambia.
      const conKg = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        recuento: 8,
        teoricoAlRecuento: 8,
        kgRecuento: 952,
      );
      const sinKg = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        recuento: 8,
        teoricoAlRecuento: 8,
      );
      expect(conKg.cierra, isTrue);
      expect(sinKg.cierra, isTrue);
      expect(conKg.teorico, sinKg.teorico);
    });

    test('el stock suma los kg de las salidas sin remito', () {
      final salidas = [
        DepositoMovimiento(
          clase: DepositoMovimiento.claseSalida,
          medias: 1,
          kgsPorMedia: [118],
        ),
        DepositoMovimiento(
          clase: DepositoMovimiento.claseSalida,
          medias: 1,
          kgsPorMedia: [122],
        ),
      ];
      final stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        salidasPendientes: 2,
        pendientes: salidas,
      );
      expect(stock.kgPendientes, 240);
      expect(stock.teorico, 8);
    });
  });

  group('DepositoConfig', () {
    test('devuelve el inicial de cada stock por separado', () {
      final config = DepositoConfig(mediasNovillo: 12, mediasCerdo: 3);
      expect(config.inicialDe(Proveedor.tipoNovillo), 12);
      expect(config.inicialDe(Proveedor.tipoCerdo), 3);
    });

    test('toMap manda `unica` para que el upsert tenga por dónde agarrar', () {
      expect(DepositoConfig().toMap()['unica'], true);
    });
  });

  group('formato de medias', () {
    test('sin decimales cuando son enteras', () {
      expect(formatMedias(8), '8');
      expect(formatMedias(200), '200');
    });

    test('hasta dos decimales cuando hay cortes', () {
      expect(formatMedias(1 / 3), '0,33');
      expect(formatMedias(10.5), '10,5');
    });

    test('la unidad se ajusta al número', () {
      expect(formatMediasConUnidad(1), '1 media');
      expect(formatMediasConUnidad(8), '8 medias');
      expect(formatMediasConUnidad(0), '0 medias');
    });
  });
}
