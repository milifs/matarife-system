// Qué pantallas pueden mostrar un saldo equivocado, y cuáles no pueden.
//
// Bajo RLS una tabla denegada vuelve **vacía, no con error**, así que
// `saldo = remitos − pagos ± notas` sin los pagos da un número MÁS ALTO que
// el real. Las pantallas se defienden mirando `AppProvider.saldosConfiables`.
//
// Pero en varios módulos esa defensa **no puede llegar a hacer falta**,
// porque el permiso que abre la pantalla es el mismo que da lectura sobre sus
// tablas. Eso no es una casualidad afortunada: es la razón por la que esos
// archivos no se tocaron. Los casos de acá son lo que hace que, si alguien
// mueve un permiso de un lado y no del otro, se entere con un test rojo y no
// con un saldo inflado en producción.

import 'package:flutter_test/flutter_test.dart';

import 'package:don_chacho_matarife/utils/app_config.dart';
import 'package:don_chacho_matarife/utils/formatters.dart';
import 'package:don_chacho_matarife/utils/lectura_permitida.dart';

void main() {
  group('el interruptor', () {
    test('viene apagado', () {
      // Si esto se pone en true por accidente, la app empieza a recortar
      // queries contra una base que todavía no niega nada: los roles sin
      // `ver_consultas` dejarían de ver cosas que hoy ven, sin que nadie
      // haya tocado la base. Se enciende con
      // --dart-define=RLS_ENCENDIDO=true y nunca a mano acá.
      //
      // ESTE TEST FALLA A PROPÓSITO si corrés la suite con ese define
      // (`flutter test --dart-define=RLS_ENCENDIDO=true`). Es el único que
      // falla, y que falle es la señal de que el define llegó.
      expect(AppConfig.rlsEncendido, isFalse);
    });
  });

  group('el admin', () {
    test('siempre tiene los saldos disponibles', () {
      // Por esto `home_screen.dart` no necesita ninguna guarda: su línea 102
      // (`if (!app.esAdmin) return _inicioSinPlata(app)`) deja entrar solo al
      // admin, y el admin pasa todos los `tiene()`. Si esta propiedad se
      // rompiera, el dashboard del dueño pasaría a ser la única pantalla con
      // plata que puede mentir sin avisar.
      const admin = LecturaPermitida(esAdmin: true);
      expect(admin.saldosConfiables, isTrue);
      expect(admin.puedeVerSaldo, isTrue);
    });
  });

  group('el permiso que abre el módulo da lectura sobre sus tablas', () {
    test('Proveedores: gestionar_proveedores', () {
      // `main.dart:331` abre la pestaña Proveedores con `gestionar_proveedores`
      // y nada más. Los saldos de proveedor (`saldoProveedor`, `saldoDeCarga`,
      // `saldoAnteriorDeCarga`) se calculan en vivo sobre `cargas` y
      // `carga_pagos`, así que sin esas tablas darían "no se le debe nada a
      // nadie" — el mismo error que el saldo de cliente, para el otro lado.
      //
      // No puede pasar: es un solo permiso para la pantalla y para las tres
      // tablas. Por eso `proveedores_screen`, `carga_detalle_screen`,
      // `carga_form_screen` y `gestion_proveedores_screen` no se tocaron.
      const prov = LecturaPermitida(permisos: {'gestionar_proveedores'});
      expect(prov.puedeLeer(TablaLectura.proveedores), isTrue);
      expect(prov.puedeLeer(TablaLectura.cargas), isTrue);
      expect(prov.puedeLeer(TablaLectura.cargaPagos), isTrue);
    });

    test('Depósito: gestionar_deposito', () {
      const dep = LecturaPermitida(permisos: {'gestionar_deposito'});
      expect(dep.puedeLeer(TablaLectura.depositoConfig), isTrue);
      expect(dep.puedeLeer(TablaLectura.depositoMovimientos), isTrue);
    });

    test('Costos: gestionar_costos', () {
      const costos = LecturaPermitida(permisos: {'gestionar_costos'});
      expect(costos.puedeLeer(TablaLectura.costosSemana), isTrue);
    });
  });

  group('los permisos que SÍ llegan a una pantalla con saldo de cliente', () {
    // Estos son los cuatro arms de la regla del saldo. Para cada uno, el rol
    // armado con ese permiso SOLO tiene que poder leer las tres tablas: es lo
    // que hace que la guarda de las pantallas sea defensa en profundidad y no
    // el camino normal.
    for (final permiso in [
      'ver_consultas',
      'crear_pago',
      'gestionar_clientes',
      'gestionar_vendedores',
    ]) {
      test('$permiso solo ya da los tres', () {
        final rol = LecturaPermitida(permisos: {permiso});
        expect(rol.puedeLeer(TablaLectura.remitos), isTrue);
        expect(rol.puedeLeer(TablaLectura.pagos), isTrue);
        expect(rol.puedeLeer(TablaLectura.notasCreditoDebito), isTrue);
        expect(rol.saldosConfiables, isTrue);
      });
    }

    test('crear_remito NO alcanza, y por eso la guarda existe', () {
      // Es el único permiso real que da `remitos` sin dar `pagos`: la
      // combinación exacta que infla. Un rol armado a mano solo con
      // `crear_remito` llega a la pantalla de remitos, no a una de saldos —
      // pero si mañana alguien le suma un permiso que abra Clientes sin
      // sumarle `ver_consultas`, la guarda es lo único que lo frena.
      const soloRemitos = LecturaPermitida(permisos: {'crear_remito'});
      expect(soloRemitos.puedeLeer(TablaLectura.remitos), isTrue);
      expect(soloRemitos.puedeLeer(TablaLectura.pagos), isFalse);
      expect(soloRemitos.saldosConfiables, isFalse);
    });
  });

  group('formatPesosSaldo', () {
    test('con los saldos disponibles muestra el número', () {
      expect(formatPesosSaldo(150000, confiable: true), contains('150.000'));
    });

    test('sin los saldos disponibles NO muestra ningún número', () {
      // Lo importante no es el texto exacto: es que no aparezca una cifra.
      // Un "$ 0" sería leído como "este cliente no debe nada".
      final texto = formatPesosSaldo(0, confiable: false);
      expect(texto, textoSaldoNoDisponible);
      expect(texto, isNot(contains('0')));
      expect(texto, isNot(contains('\$')));
    });

    test('tampoco muestra el número cuando el saldo calculado no es 0', () {
      // No debería pasar (el provider deja los saldos en 0 cuando corta),
      // pero si alguna pantalla pasara un número propio, igual se tapa.
      expect(formatPesosSaldo(999999, confiable: false),
          textoSaldoNoDisponible);
    });
  });
}
