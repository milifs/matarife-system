// Qué tablas puede leer cada rol (Fase 2 de auth).
//
// Este archivo es el **contrato entre la app y las políticas de RLS**. Lo que
// se fija acá tiene que coincidir con `supabase_migration_rls_politicas.sql`:
// son dos fuentes de verdad y estos casos son lo que hace que una se note
// cuando la otra cambia.
//
// Los roles de los grupos son los de producción al 29/10/2026, con los
// permisos que tienen en `rol_permisos`.

import 'package:flutter_test/flutter_test.dart';

import 'package:don_chacho_matarife/utils/lectura_permitida.dart';

void main() {
  // ── Los cuatro roles reales ──
  const admin = LecturaPermitida(esAdmin: true);

  const secretaria = LecturaPermitida(permisos: {
    'crear_remito',
    'editar_remito',
    'crear_pago',
    'gestionar_clientes',
    'gestionar_vendedores',
    'ver_consultas',
    'gestionar_proveedores',
    'gestionar_deposito',
    'ver_kg_semana',
  });

  const cobrador = LecturaPermitida(permisos: {
    'crear_pago',
    'editar_pago',
    'gestionar_clientes',
    'gestionar_vendedores',
    'ver_consultas',
  });

  const deposito = LecturaPermitida(permisos: {'gestionar_deposito'});

  group('el admin lee todo', () {
    test('cualquier tabla', () {
      for (final t in [
        TablaLectura.pagos,
        TablaLectura.costosSemana,
        TablaLectura.cargas,
        TablaLectura.depositoMovimientos,
        TablaLectura.notasCreditoDebito,
      ]) {
        expect(admin.puedeLeer(t), isTrue, reason: t);
      }
    });

    test('es_admin no necesita la fila en rol_permisos', () {
      // Mismo criterio que `Rol.tienePermiso` en Dart y que el
      // `r.es_admin OR ...` de las funciones SQL. Si los tres no coincidieran,
      // el dueño vería un botón que la base le rechaza.
      expect(admin.permisos, isEmpty);
      expect(admin.tiene('gestionar_costos'), isTrue);
    });
  });

  group('la regla del saldo', () {
    test('la cumplen los tres roles que llegan a una pantalla con saldo', () {
      expect(secretaria.puedeVerSaldo, isTrue);
      expect(cobrador.puedeVerSaldo, isTrue);
      expect(admin.puedeVerSaldo, isTrue);
    });

    test('el encargado de depósito no la cumple', () {
      expect(deposito.puedeVerSaldo, isFalse);
    });

    test('gestionar_clientes SOLO ya la cumple', () {
      // Es el caso que motivó la regla. La pestaña Clientes muestra el saldo
      // de cada cliente en pesos y su gate es `gestionar_clientes`, así que un
      // rol armado con ese permiso y sin `ver_consultas` **tiene** que poder
      // leer pagos. Si no, esa columna de pesos saldría inflada y sin aviso.
      const rolArmadoAMano = LecturaPermitida(permisos: {'gestionar_clientes'});
      expect(rolArmadoAMano.puedeVerSaldo, isTrue);
      expect(rolArmadoAMano.puedeLeer(TablaLectura.pagos), isTrue);
      expect(rolArmadoAMano.saldosConfiables, isTrue);
    });

    test('gestionar_vendedores SOLO también', () {
      const rolArmadoAMano =
          LecturaPermitida(permisos: {'gestionar_vendedores'});
      expect(rolArmadoAMano.puedeVerSaldo, isTrue);
      expect(rolArmadoAMano.saldosConfiables, isTrue);
    });

    test('un permiso que no abre ninguna pantalla con saldo no la cumple', () {
      const soloRemitos = LecturaPermitida(permisos: {'crear_remito'});
      expect(soloRemitos.puedeVerSaldo, isFalse);
      // Pero sí puede leer remitos: los necesita para numerar el próximo.
      expect(soloRemitos.puedeLeer(TablaLectura.remitos), isTrue);
      // Y justamente por eso sus saldos NO son confiables: tiene los remitos
      // y no los pagos, que es la combinación que infla.
      expect(soloRemitos.saldosConfiables, isFalse);
    });
  });

  group('saldosConfiables', () {
    test('exige las TRES tablas del saldo, no dos', () {
      expect(secretaria.saldosConfiables, isTrue);
      expect(cobrador.saldosConfiables, isTrue);
      expect(deposito.saldosConfiables, isFalse);
    });

    test('sin usuario no hay nada confiable', () {
      expect(LecturaPermitida.nada.saldosConfiables, isFalse);
      expect(LecturaPermitida.nada.puedeVerSaldo, isFalse);
    });

    test('con RLS apagado todo es confiable', () {
      // `LecturaPermitida.todo` es lo que usa el provider mientras ninguna
      // tabla tenga RLS encendido: la base no niega nada.
      expect(LecturaPermitida.todo.saldosConfiables, isTrue);
      expect(LecturaPermitida.todo.puedeLeer(TablaLectura.pagos), isTrue);
    });
  });

  group('el encargado de depósito', () {
    test('lee lo del depósito', () {
      expect(deposito.puedeLeer(TablaLectura.depositoConfig), isTrue);
      expect(deposito.puedeLeer(TablaLectura.depositoMovimientos), isTrue);
    });

    test('NO lee plata', () {
      expect(deposito.puedeLeer(TablaLectura.pagos), isFalse);
      expect(deposito.puedeLeer(TablaLectura.pagoMedios), isFalse);
      expect(deposito.puedeLeer(TablaLectura.notasCreditoDebito), isFalse);
      expect(deposito.puedeLeer(TablaLectura.costosSemana), isFalse);
    });

    test('NO lee remitos ni cargas', () {
      // Es el recorte que habilitó la PR #20 (mergeada): desde que el depósito es el
      // registro de lo que hay y no se reconcilia contra remitos,
      // `cargarDeposito` lee solo deposito_config y deposito_movimientos.
      // Si esto se vuelve a poner en true, la matriz quedó desactualizada.
      expect(deposito.puedeLeer(TablaLectura.remitos), isFalse);
      expect(deposito.puedeLeer(TablaLectura.remitoItems), isFalse);
      expect(deposito.puedeLeer(TablaLectura.cargas), isFalse);
      expect(deposito.puedeLeer(TablaLectura.proveedores), isFalse);
    });
  });

  group('el cobrador', () {
    test('lee la plata de los clientes pero no las compras', () {
      expect(cobrador.puedeLeer(TablaLectura.pagos), isTrue);
      expect(cobrador.puedeLeer(TablaLectura.notasCreditoDebito), isTrue);
      expect(cobrador.puedeLeer(TablaLectura.cargas), isFalse);
      expect(cobrador.puedeLeer(TablaLectura.cargaPagos), isFalse);
    });

    test('no lee el costo por kg, que es el margen', () {
      expect(cobrador.puedeLeer(TablaLectura.costosSemana), isFalse);
    });

    test('lee la auditoría de eliminados, que es parte de Consultas', () {
      expect(cobrador.puedeLeer(TablaLectura.pagosEliminados), isTrue);
      expect(cobrador.puedeLeer(TablaLectura.remitosEliminados), isTrue);
    });
  });

  group('la secretaria', () {
    test('lee proveedores y depósito, que son los módulos de la cajera', () {
      expect(secretaria.puedeLeer(TablaLectura.proveedores), isTrue);
      expect(secretaria.puedeLeer(TablaLectura.cargas), isTrue);
      expect(secretaria.puedeLeer(TablaLectura.depositoMovimientos), isTrue);
    });

    test('no lee el costo por kg', () {
      expect(secretaria.puedeLeer(TablaLectura.costosSemana), isFalse);
    });
  });

  group('las tablas abiertas no figuran acá', () {
    test('una tabla que no está en la lista se da por legible', () {
      // clientes, vendedores, reparto_*, permisos, roles, rol_permisos: las
      // puede leer cualquier usuario activo, así que no hay rol que las
      // pierda y no hace falta listarlas. El que niega de verdad es Postgres;
      // este archivo solo evita preguntar de más.
      expect(deposito.puedeLeer('clientes'), isTrue);
      expect(deposito.puedeLeer('reparto_listas'), isTrue);
      expect(LecturaPermitida.nada.puedeLeer('una_tabla_que_no_existe'),
          isTrue);
    });
  });

  group('noLegiblesDe', () {
    test('devuelve solo las que el rol no puede leer', () {
      final sinPermiso = deposito.noLegiblesDe([
        TablaLectura.pagos,
        TablaLectura.depositoMovimientos,
        TablaLectura.costosSemana,
      ]);
      expect(sinPermiso, {TablaLectura.pagos, TablaLectura.costosSemana});
    });

    test('para el admin siempre es vacío', () {
      expect(admin.noLegiblesDe([TablaLectura.pagos, TablaLectura.cargas]),
          isEmpty);
    });
  });

  group('ver_kg_semana da lectura sobre los remitos', () {
    // Las dos tarjetas de kg del Inicio salen de `remito_items`. Bajo RLS,
    // sin lectura no habría error: saldrían en cero, que es peor.
    const soloKg = LecturaPermitida(permisos: {'ver_kg_semana'});

    test('un rol con ese permiso solo lee remitos y sus ítems', () {
      expect(soloKg.puedeLeer(TablaLectura.remitos), isTrue);
      expect(soloKg.puedeLeer(TablaLectura.remitoItems), isTrue);
    });

    test('pero no la plata', () {
      // El permiso es un recorte del dashboard, no una puerta al saldo.
      expect(soloKg.puedeVerSaldo, isFalse);
      expect(soloKg.puedeLeer(TablaLectura.pagos), isFalse);
      expect(soloKg.puedeLeer(TablaLectura.notasCreditoDebito), isFalse);
      expect(soloKg.puedeLeer(TablaLectura.costosSemana), isFalse);
    });

    test('y sus saldos no son confiables, así que no se muestran', () {
      // Lee remitos y no pagos: exactamente el caso que infla los saldos.
      expect(soloKg.saldosConfiables, isFalse);
    });

    test('a la Secretaria no le cambia nada: ya leía remitos', () {
      // Tiene `crear_remito` desde siempre. El arm nuevo está por los roles
      // que el admin puede armar, no por ella.
      expect(secretaria.puedeLeer(TablaLectura.remitos), isTrue);
    });
  });
}
