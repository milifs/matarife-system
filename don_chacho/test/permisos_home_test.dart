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
    'ver_kg_semana',
  ]);
  final deposito = rol('Encargado de Deposito', permisos: ['gestionar_deposito']);
  final secretaria = rol('Secretaria', permisos: [
    'crear_remito',
    'crear_pago',
    'gestionar_clientes',
    'ver_consultas',
    'gestionar_deposito',
    'ver_kg_semana',
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

  group('las dos tarjetas de kg piden ver_kg_semana', () {
    // Pedido de Joaquín: que la secretaria vea los kg de novillo y de cerdo
    // de la semana, y nada más de Inicio. Es el primer recorte del dashboard
    // que se le puede dar a un rol, así que lo que importa es que sea un
    // recorte y no una puerta: el permiso no vuelve admin a nadie.

    test('la Secretaria lo tiene', () {
      expect(secretaria.tienePermiso('ver_kg_semana'), isTrue);
    });

    test('y sigue sin ser admin', () {
      // Ve el Inicio recortado (`_inicioKgSemana`), no el dashboard: el
      // saldo a cobrar, los costos, las ganancias y la deuda de los
      // vendedores quedan del otro lado del `if (!app.esAdmin)`.
      expect(usuarioCon(secretaria).esAdmin, isFalse);
    });

    test('Rocío Cejas no lo ve: el Encargado de Depósito no lo tiene', () {
      // La otra mitad del pedido. Su rol sigue con un solo permiso, así que
      // le queda el Inicio sin plata de v19.14.
      expect(deposito.tienePermiso('ver_kg_semana'), isFalse);
      expect(deposito.permisoIds, ['gestionar_deposito']);
    });

    test('el Cobrador tampoco', () {
      // No se lo pidió nadie. Si algún día lo necesita, es una fila en
      // rol_permisos desde Gestión de Usuarios, no un cambio de código.
      expect(cobrador.tienePermiso('ver_kg_semana'), isFalse);
    });

    test('el admin lo tiene por es_admin, aunque no lo necesite', () {
      // Él ve el dashboard entero por rol; el permiso está para que no haya
      // ninguno que el administrador no tenga.
      expect(admin.tienePermiso('ver_kg_semana'), isTrue);
    });
  });
}
