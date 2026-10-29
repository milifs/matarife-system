// Fija la aritmética del depósito, que desde v19.16 es deliberadamente
// chica: el módulo es el LIBRO de lo que hay en la cámara y nada más.
//
//   lo que debería haber = arranque + entradas - salidas
//
// Lo que se protege acá:
//   1. Que la cuenta sea esa y solo esa. Hasta v19.15 el stock también sumaba
//      las cargas de proveedores (animales × 2) y restaba los remitos
//      confirmados, con tabla de equivalencias de cortes y cierre por FIFO de
//      las salidas que esperaban remito. Todo eso se sacó: el depósito
//      registra lo que hay, no lo reconcilia con lo comprado ni lo facturado.
//   2. Que el recuento NO mueva el stock: es la foto contra la cual comparar.
//   3. Los dos stocks separados: una media de cerdo no puede tapar un
//      faltante de novillo.
//   4. El veredicto: faltan / sobran / dan redondos, con su tolerancia.
//   5. Que los kilos sigan siendo informativos y sepan decir cuándo están
//      incompletos.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';
import 'package:don_chacho_matarife/utils/formatters.dart';

void main() {
  group('la cuenta del stock', () {
    test('el teórico es arranque + entradas - salidas', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        entradas: 6,
        salidas: 4,
      );
      expect(stock.teorico, 12);
    });

    test('sin movimientos, el stock es el arranque', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 8,
      );
      expect(stock.teorico, 8);
    });

    test('un arranque en cero sin movimientos da cero', () {
      // El caso que disparó la reescritura: con el arranque en 0 el módulo
      // mostraba −10 porque le restaba un remito del día. Ahora no mira
      // remitos, así que un libro vacío da 0 y no un negativo inexplicable.
      const stock = StockDeposito(tipo: Proveedor.tipoNovillo);
      expect(stock.teorico, 0);
    });

    test('el stock puede quedar negativo y se muestra como tal', () {
      // Físicamente imposible, pero es lo honesto: significa que se cargó
      // una salida sin su entrada. Taparlo con un cero esconde el error de
      // carga, que es justo lo que hay que ver.
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 2,
        salidas: 5,
      );
      expect(stock.teorico, -3);
    });

    test('las medias con decimales no se redondean', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 3.5,
        entradas: 0.25,
        salidas: 1,
      );
      expect(stock.teorico, closeTo(2.75, 1e-12));
    });

    test('sin recuento no hay con qué comparar', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
      );
      expect(stock.tieneRecuento, isFalse);
      expect(stock.diferencia, isNull);
      expect(stock.cierra, isFalse);
      expect(stock.faltan, isFalse);
      expect(stock.sobran, isFalse);
    });

    test('la etiqueta del tipo', () {
      expect(
        const StockDeposito(tipo: Proveedor.tipoNovillo).tipoLabel,
        'Novillo',
      );
      expect(
        const StockDeposito(tipo: Proveedor.tipoCerdo).tipoLabel,
        'Cerdo',
      );
    });
  });

  group('el veredicto', () {
    // El recuento se compara contra lo que el libro decía EN SU MOMENTO
    // (`teoricoAlRecuento`), no contra el de hoy: si no, un movimiento
    // posterior al último recuento aparecería como una diferencia.

    test('faltan medias cuando el recuento es menor que el teórico', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        teoricoAlRecuento: 10,
        recuento: 8,
      );
      expect(stock.diferencia, 2);
      expect(stock.faltan, isTrue);
      expect(stock.sobran, isFalse);
      expect(stock.cierra, isFalse);
      expect(stock.faltantes, 2);
      expect(stock.sobrantes, 0);
    });

    test('sobran medias cuando el recuento es mayor que el teórico', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        teoricoAlRecuento: 10,
        recuento: 12,
      );
      expect(stock.diferencia, -2);
      expect(stock.sobran, isTrue);
      expect(stock.faltan, isFalse);
      expect(stock.sobrantes, 2);
      expect(stock.faltantes, 0);
    });

    test('los números dan redondos cuando coinciden', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        teoricoAlRecuento: 10,
        recuento: 10,
      );
      expect(stock.cierra, isTrue);
      expect(stock.faltan, isFalse);
      expect(stock.sobran, isFalse);
      expect(stock.diferencia, 0);
    });

    test('un resto de coma flotante no enciende la alerta', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        teoricoAlRecuento: 10.000000001,
        recuento: 10,
      );
      expect(stock.cierra, isTrue);
      expect(stock.faltan, isFalse);
    });

    test('media media de diferencia sí enciende la alerta', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        teoricoAlRecuento: 10,
        recuento: 9.5,
      );
      expect(stock.cierra, isFalse);
      expect(stock.faltan, isTrue);
      expect(stock.faltantes, closeTo(0.5, 1e-12));
    });

    test('el recuento de hoy no se compara contra el teórico de hoy', () {
      // Se contaron 10 y después entraron 200. El libro de hoy dice 210,
      // pero el veredicto mira el de aquel momento: los números dan.
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        entradas: 200,
        teoricoAlRecuento: 10,
        recuento: 10,
      );
      expect(stock.teorico, 210);
      expect(stock.cierra, isTrue);
      expect(stock.faltan, isFalse);
    });

    test('un recuento sin teórico de su momento no alcanza para comparar', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        recuento: 10,
      );
      expect(stock.tieneRecuento, isFalse);
      expect(stock.diferencia, isNull);
    });
  });

  group('el circuito de Rocío', () {
    // Entra la carne, sale la carne, se cuenta la cámara. Los tres pasos se
    // cargan a mano: el módulo no se enteró de ninguna compra ni de ningún
    // remito, y no tiene por qué.

    test('una entrada de 10 y una salida de 2 dejan 8 en la cámara', () {
      final entrada = DepositoMovimiento(
        tipo: Proveedor.tipoNovillo,
        clase: DepositoMovimiento.claseEntrada,
        medias: 10,
        observacion: 'Llegó la faena',
      );
      final salida = DepositoMovimiento(
        tipo: Proveedor.tipoNovillo,
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        observacion: 'Se las llevó Firme',
      );

      expect(entrada.esEntrada, isTrue);
      expect(salida.esSalida, isTrue);

      final stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        entradas: entrada.medias,
        salidas: salida.medias,
      );
      expect(stock.teorico, 8);
    });

    test('todas las salidas descuentan igual, sea el motivo que sea', () {
      // Hasta v19.15 una salida podía ser "pendiente de remito" o
      // "definitiva" y la cuenta las trataba distinto. Ahora no: el motivo
      // vive en la observación y no cambia el número.
      final seLaLlevoUnCliente = DepositoMovimiento(
        tipo: Proveedor.tipoNovillo,
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        observacion: 'Se las llevó Firme',
      );
      final merma = DepositoMovimiento(
        tipo: Proveedor.tipoNovillo,
        clase: DepositoMovimiento.claseSalida,
        medias: 1,
        observacion: 'Merma',
      );
      expect(seLaLlevoUnCliente.esSalida, isTrue);
      expect(merma.esSalida, isTrue);

      final stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        salidas: seLaLlevoUnCliente.medias + merma.medias,
      );
      expect(stock.teorico, 7);
    });

    test('el recuento no mueve el stock: es solo la foto', () {
      final recuento = DepositoMovimiento(
        tipo: Proveedor.tipoNovillo,
        clase: DepositoMovimiento.claseRecuento,
        medias: 8,
      );
      expect(recuento.esRecuento, isTrue);
      expect(recuento.esEntrada, isFalse);
      expect(recuento.esSalida, isFalse);

      // El recuento entra por `recuento`, nunca por entradas ni salidas.
      final stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        salidas: 2,
        teoricoAlRecuento: 8,
        recuento: recuento.medias,
      );
      expect(stock.teorico, 8);
      expect(stock.cierra, isTrue);
    });

    test('la media que salió sin registrarse aparece en el recuento', () {
      // El agujero original, que este módulo sigue tapando sin mirar remitos:
      // el libro dice 10, en la cámara hay 8.
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        teoricoAlRecuento: 10,
        recuento: 8,
      );
      expect(stock.faltantes, 2);
    });

    test('novillo y cerdo se cuentan aparte', () {
      const novillo = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        salidas: 4,
        teoricoAlRecuento: 6,
        recuento: 4,
      );
      const cerdo = StockDeposito(
        tipo: Proveedor.tipoCerdo,
        inicial: 5,
        teoricoAlRecuento: 5,
        recuento: 5,
      );
      // El cerdo cierra y el novillo no: el sobrante de uno no tapa al otro.
      expect(cerdo.cierra, isTrue);
      expect(novillo.faltan, isTrue);
      expect(novillo.faltantes, 2);
    });
  });

  group('DepositoMovimiento', () {
    test('el número se formatea D-0001 y no se manda si no existe', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 1,
      );
      // Lo asigna la secuencia de Postgres, no la app.
      expect(mov.numero, 0);
      expect(mov.toMap().containsKey('numero'), isFalse);

      mov.numero = 7;
      expect(mov.numeroFormateado, 'D-0007');
      expect(mov.toMap()['numero'], 7);
    });

    test('las etiquetas de clase y tipo', () {
      final entrada = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        tipo: Proveedor.tipoNovillo,
      );
      final salida = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        tipo: Proveedor.tipoCerdo,
      );
      final recuento = DepositoMovimiento(
        clase: DepositoMovimiento.claseRecuento,
      );
      expect(entrada.claseLabel, 'Entrada');
      expect(salida.claseLabel, 'Salida');
      expect(recuento.claseLabel, 'Recuento');
      expect(entrada.tipoLabel, 'Novillo');
      expect(salida.tipoLabel, 'Cerdo');
    });

    test('fromMap cae en novillo si el tipo viene raro', () {
      final mov = DepositoMovimiento.fromMap({
        'clase': DepositoMovimiento.claseEntrada,
        'medias': 3,
        'tipo': 'cualquier cosa',
      });
      expect(mov.tipo, Proveedor.tipoNovillo);
      expect(mov.medias, 3);
    });

    test('toMap ya no manda espera_remito', () {
      // La columna sigue en la tabla con su DEFAULT, así que no hizo falta
      // migración; lo que se fue es la distinción, que colgaba de los remitos.
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
      );
      expect(mov.toMap().containsKey('espera_remito'), isFalse);
    });

    test('fromMap ignora espera_remito si la fila vieja lo trae', () {
      final mov = DepositoMovimiento.fromMap({
        'clase': DepositoMovimiento.claseSalida,
        'medias': 2,
        'espera_remito': true,
      });
      expect(mov.esSalida, isTrue);
      expect(mov.medias, 2);
    });

    test('la baja arrastra el motivo y los datos del movimiento', () {
      final mov = DepositoMovimiento(
        numero: 12,
        tipo: Proveedor.tipoCerdo,
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        observacion: 'Para La Florida',
      );
      final baja = DepositoMovimientoEliminado.desde(
        mov,
        observacion: 'Me equivoqué de tipo',
        eliminadoPor: 'Rocio',
      );
      expect(baja.movimientoId, mov.id);
      expect(baja.movimientoNumero, 12);
      expect(baja.tipo, Proveedor.tipoCerdo);
      expect(baja.clase, DepositoMovimiento.claseSalida);
      expect(baja.medias, 2);
      expect(baja.observacionOriginal, 'Para La Florida');
      expect(baja.observacion, 'Me equivoqué de tipo');
      expect(baja.eliminadoPor, 'Rocio');
      expect(baja.toMap().containsKey('espera_remito'), isFalse);
    });
  });

  group('kg por media', () {
    // Un kilo por cada media (no un total): dos medias pueden diferenciarse
    // en 40 kg. Son OPCIONALES — si el campo frenara el registro cuando no
    // hay balanza a mano, la salida no se registraría.

    test('el total es la suma de los kg cargados', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 3,
        kgsPorMedia: [118, 95, 102.5],
      );
      expect(mov.totalKg, closeTo(315.5, 1e-9));
      expect(mov.tieneKg, isTrue);
      expect(mov.mediasSinPesar, 0);
    });

    test('un movimiento sin pesar no rompe nada', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
      );
      expect(mov.totalKg, 0);
      expect(mov.tieneKg, isFalse);
      expect(mov.mediasSinPesar, 2);
    });

    test('avisa cuántas medias quedaron sin pesar', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 4,
        kgsPorMedia: [110, 108],
      );
      expect(mov.mediasSinPesar, 2);
    });

    test('una media fraccionada cuenta como una a pesar', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 0.5,
      );
      expect(mov.mediasSinPesar, 1);
    });

    test('pesar de más no da negativo', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 1,
        kgsPorMedia: [100, 105, 98],
      );
      expect(mov.mediasSinPesar, 0);
    });

    test('los kg viajan al toMap como lista', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseEntrada,
        medias: 2,
        kgsPorMedia: [118, 95],
      );
      expect(mov.toMap()['kgs_por_media'], [118, 95]);
    });

    test('fromMap tolera que la columna no exista', () {
      final mov = DepositoMovimiento.fromMap({
        'clase': DepositoMovimiento.claseEntrada,
        'medias': 2,
      });
      expect(mov.kgsPorMedia, isEmpty);
      expect(mov.totalKg, 0);
    });

    test('fromMap descarta basura en vez de romper la pantalla', () {
      final mov = DepositoMovimiento.fromMap({
        'clase': DepositoMovimiento.claseEntrada,
        'medias': 3,
        'kgs_por_media': [118, 'ochenta', null, 95],
      });
      expect(mov.kgsPorMedia, [118, 95]);
      expect(mov.totalKg, 213);
    });

    test('la baja se lleva los kg para poder reconstruir el movimiento', () {
      final mov = DepositoMovimiento(
        clase: DepositoMovimiento.claseSalida,
        medias: 2,
        kgsPorMedia: [118, 95],
      );
      final baja = DepositoMovimientoEliminado.desde(
        mov,
        observacion: 'Duplicada',
      );
      expect(baja.kgsPorMedia, [118, 95]);
      expect(baja.toMap()['kgs_por_media'], [118, 95]);
    });
  });

  group('los kilos del stock', () {
    test('el kg teórico sigue la misma cuenta que las medias', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 4,
        entradas: 2,
        salidas: 1,
        kgInicial: 440,
        kgEntradas: 220,
        kgSalidas: 110,
      );
      expect(stock.teorico, 5);
      expect(stock.kgTeorico, 550);
      expect(stock.tieneKg, isTrue);
      expect(stock.kgIncompleto, isFalse);
    });

    test('nunca da negativo: sería lo que falta pesar, no un faltante', () {
      // Salió carne pesada de una entrada que nadie pesó. El kilaje queda
      // incompleto, y un negativo haría pensar en un faltante que no existe.
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        salidas: 2,
        kgSalidas: 230,
        mediasSinPesar: 10,
      );
      expect(stock.kgTeorico, 0);
      expect(stock.tieneKg, isFalse);
      expect(stock.kgIncompleto, isTrue);
    });

    test('avisa cuando hay medias sin pesar', () {
      const stock = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 4,
        entradas: 2,
        kgInicial: 440,
        mediasSinPesar: 2,
      );
      expect(stock.kgTeorico, 440);
      expect(stock.tieneKg, isTrue);
      expect(stock.kgIncompleto, isTrue);
    });

    test('los kilos no cambian el veredicto, que es por medias', () {
      // Mismo stock en medias, kilajes distintos: el veredicto es el mismo.
      const sinKg = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        teoricoAlRecuento: 10,
        recuento: 8,
      );
      const conKg = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        inicial: 10,
        kgInicial: 1100,
        kgRecuento: 880,
        teoricoAlRecuento: 10,
        recuento: 8,
      );
      expect(sinKg.faltantes, 2);
      expect(conKg.faltantes, 2);
      expect(conKg.cierra, sinKg.cierra);
    });

    test('un kilaje incompleto se mide con la tolerancia de medias', () {
      const nada = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        kgInicial: 100,
        mediasSinPesar: 0,
      );
      const resto = StockDeposito(
        tipo: Proveedor.tipoNovillo,
        kgInicial: 100,
        mediasSinPesar: 0.001,
      );
      expect(nada.kgIncompleto, isFalse);
      expect(resto.kgIncompleto, isFalse);
    });
  });

  group('DepositoConfig', () {
    test('devuelve el inicial de cada stock por separado', () {
      final config = DepositoConfig(mediasNovillo: 10, mediasCerdo: 4);
      expect(config.inicialDe(Proveedor.tipoNovillo), 10);
      expect(config.inicialDe(Proveedor.tipoCerdo), 4);
    });

    test('toMap manda `unica` para que el upsert tenga por dónde agarrar', () {
      expect(DepositoConfig().toMap()['unica'], isTrue);
    });

    test('devuelve los kg del arranque de cada stock', () {
      final config = DepositoConfig(kgNovillo: 1100, kgCerdo: 320);
      expect(config.kgInicialDe(Proveedor.tipoNovillo), 1100);
      expect(config.kgInicialDe(Proveedor.tipoCerdo), 320);
    });

    test('un arranque sin pesar queda en cero, no rompe', () {
      final config = DepositoConfig(mediasNovillo: 8);
      expect(config.kgInicialDe(Proveedor.tipoNovillo), 0);
      expect(config.kgInicialDe(Proveedor.tipoCerdo), 0);
    });
  });

  group('formato de medias', () {
    test('sin decimales cuando son enteras', () {
      expect(formatMedias(8), '8');
      expect(formatMedias(200), '200');
    });

    test('hasta dos decimales cuando hay fracciones', () {
      expect(formatMedias(0.5), '0,5');
      expect(formatMedias(10.5), '10,5');
    });

    test('la unidad se ajusta al número', () {
      expect(formatMediasConUnidad(1), '1 media');
      expect(formatMediasConUnidad(8), '8 medias');
      expect(formatMediasConUnidad(0), '0 medias');
    });
  });
}
