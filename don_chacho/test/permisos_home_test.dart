// Fija quién puede ver la plata del negocio.
//
// El Encargado de Depósito entraba a la app y la pantalla de Inicio le
// mostraba el SALDO TOTAL A COBRAR del negocio y la deuda de cada vendedor.
// Su rol tiene un solo permiso (`gestionar_deposito`): no tiene ninguna otra
// pantalla con plata, y esa la veía igual porque Inicio no miraba el rol.
//
// Lo que se protege acá es la REGLA, que es lo que se puede probar sin
// levantar la UI: qué rol es admin y qué permisos tiene cada uno. El gate de
// la pantalla (`if (!app.esAdmin)`) y el del menú (`tiene('crear_pago')`)
// salen de estos mismos valores.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';

Rol rol(String nombre,
        {bool admin = false, List<String> permisos = const []}) =>
    Rol(
      nombre: nombre,
      esAdmin: admin,
      permisoIds: permisos,
    );

Usuario usuarioCon(Rol r) => Usuario(
      usuario: 'u',
      passwordHash: 'x',
      rolId: r.id,
      nombreCompleto: 'Quien Sea',
      rol: r,
    );

void main() {
  // Los roles reales de producción, al 28/10/2026.
  final admin = rol('Administrador', admin: true, permisos: [
    'crear_remito',
    'crear_pago',
    'editar_pago',
    'gestionar_clientes',
    'ver_consultas',
    'gestionar_deposito',
  ]);
  final deposito = rol('Encargado de Deposito', permisos: ['gestionar_deposito']);
  final secretaria = rol('Secretaria', permisos: [
    'crear_remito',
    'crear_pago',
    'gestionar_clientes',
    'ver_consultas',
    'gestionar_deposito',
  ]);
  final cobrador = rol('Cobrador', permisos: [
    'crear_pago',
    'editar_pago',
    'gestionar_clientes',
    'ver_consultas',
  ]);

  group('la plata del negocio es solo del dueño', () {
    test('el Encargado de Depósito NO es admin', () {
      // Es la condición que ahora corta el dashboard.
      expect(usuarioCon(deposito).esAdmin, isFalse);
      expect(usuarioCon(secretaria).esAdmin, isFalse);
      expect(usuarioCon(cobrador).esAdmin, isFalse);
      expect(usuarioCon(admin).esAdmin, isTrue);
    });

    test('el Encargado de Depósito tiene un solo permiso', () {
      // Por eso el agujero era grave: Inicio era su única pantalla, y le
      // mostraba justo lo que no tiene que ver.
      expect(deposito.permisoIds, ['gestionar_deposito']);
      expect(deposito.tienePermiso('ver_consultas'), isFalse);
      expect(deposito.tienePermiso('gestionar_clientes'), isFalse);
    });
  });

  group('la nota de crédito / débito pide crear_pago', () {
    // Mueve el saldo de un cliente igual que un pago, y la pantalla muestra
    // el saldo actual. Estaba sin ningún gate.

    test('el Encargado de Depósito no la ve', () {
      expect(deposito.tienePermiso('crear_pago'), isFalse);
    });

    test('los que la usaban la siguen viendo', () {
      // El gate tiene que tapar al depósito sin sacársela a quien la usa.
      expect(secretaria.tienePermiso('crear_pago'), isTrue);
      expect(cobrador.tienePermiso('crear_pago'), isTrue);
      expect(admin.tienePermiso('crear_pago'), isTrue);
    });
  });
}
