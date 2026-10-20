// Fija el tipo de animal del proveedor (novillo / cerdo). Importa sobre todo
// el fromMap: la columna `tipo` recién se agrega con
// supabase_migration_proveedor_tipo.sql, así que la app tiene que seguir
// leyendo filas que no la traen.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';

void main() {
  test('por defecto un proveedor nuevo es de novillo', () {
    final p = Proveedor(nombre: 'BILY SAYUS');
    expect(p.tipo, Proveedor.tipoNovillo);
    expect(p.esCerdo, isFalse);
    expect(p.tipoLabel, 'Novillo');
  });

  test('cerdo', () {
    final p = Proveedor(nombre: 'EL CHANCHO', tipo: Proveedor.tipoCerdo);
    expect(p.esCerdo, isTrue);
    expect(p.tipoLabel, 'Cerdo');
  });

  test('el tipo va al toMap en minúscula, igual que en la BD', () {
    expect(
      Proveedor(nombre: 'X', tipo: Proveedor.tipoCerdo).toMap()['tipo'],
      'cerdo',
    );
  });

  group('fromMap', () {
    Proveedor leer(Map<String, dynamic> extra) => Proveedor.fromMap({
          'id': 'p1',
          'nombre': 'BILY SAYUS',
          'desvaste_porcentaje': 5,
          'precio_kg_vivo': 5400,
          'rinde_asegurado': 58,
          'activo': true,
          'creado_en': '2026-10-16T00:00:00.000',
          ...extra,
        });

    test('sin la columna tipo (antes de la migración) cae en novillo', () {
      expect(leer({}).tipo, Proveedor.tipoNovillo);
    });

    test('tipo null cae en novillo', () {
      expect(leer({'tipo': null}).tipo, Proveedor.tipoNovillo);
    });

    test('tipo cerdo se respeta', () {
      expect(leer({'tipo': 'cerdo'}).tipo, Proveedor.tipoCerdo);
    });

    test('no importan las mayúsculas', () {
      expect(leer({'tipo': 'Cerdo'}).tipo, Proveedor.tipoCerdo);
      expect(leer({'tipo': 'CERDO'}).tipo, Proveedor.tipoCerdo);
    });

    test('cualquier otra cosa cae en novillo, no explota', () {
      expect(leer({'tipo': 'pollo'}).tipo, Proveedor.tipoNovillo);
      expect(leer({'tipo': ''}).tipo, Proveedor.tipoNovillo);
      expect(leer({'tipo': 123}).tipo, Proveedor.tipoNovillo);
    });
  });

  // El módulo de ganancia va a usar esto para elegir entre
  // costoPorKgNovillo y costoPorKgCerdo.
  test('el tipo del proveedor entra en costoPorTipo de CostoSemanal', () {
    final costo = CostoSemanal(
      semanaInicio: DateTime(2026, 10, 12),
      costoPorKgNovillo: 4100,
      costoPorKgCerdo: 2800,
    );
    final novillo = Proveedor(nombre: 'A');
    final cerdo = Proveedor(nombre: 'B', tipo: Proveedor.tipoCerdo);

    expect(costo.costoPorTipo(novillo.tipoLabel), 4100);
    expect(costo.costoPorTipo(cerdo.tipoLabel), 2800);
  });
}
