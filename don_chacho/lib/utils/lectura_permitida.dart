// ============================================================
// QUÉ TABLAS PUEDE LEER UN ROL
// ============================================================
// Bajo RLS, una tabla que el rol no puede leer **no devuelve un error:
// devuelve una lista vacía**. Y el saldo se calcula así:
//
//     saldo del cliente = remitos confirmados − pagos ± notas de crédito/débito
//
// Con `pagos` vacío por falta de permiso, esa resta se convierte en "saldo =
// todo lo que se le remitió alguna vez" y **todos los saldos salen inflados,
// con cara de dato correcto**. Ya pasó algo parecido en v18.22, cuando el
// límite de 1000 filas de PostgREST cortó la lista de pagos y nadie se
// enteró; la diferencia es que un recorte por RLS sería sistemático y por rol.
//
// Así que el provider no puede averiguar a posteriori si una tabla vino vacía
// porque no hay datos o porque no tiene permiso: **tiene que saberlo antes de
// preguntar**. Eso es lo que decide este archivo.
//
// Va acá, puro y sin Supabase ni Flutter, por la misma razón que
// `version_check.dart`: es la clase de decisión que conviene tener cubierta
// por tests, y para probarla no hace falta ni red ni base.
//
// ⚠ ESPEJO DE LAS POLÍTICAS SQL. Lo que dice este archivo tiene que coincidir
// con `supabase_migration_rls_politicas.sql`. Son dos fuentes de verdad y eso
// es un riesgo asumido: la alternativa (preguntarle a la base qué puede leer)
// serían varias consultas más en cada login. Si se cambia una política de
// SELECT, se cambia acá. `test/lectura_permitida_test.dart` fija el contrato.
// ============================================================

/// Las tablas cuya lectura depende de un permiso.
///
/// No están todas las del esquema: las que cualquier usuario activo puede
/// leer (`clientes`, `vendedores`, `reparto_*`, `permisos`, `roles`,
/// `rol_permisos`) no hacen falta acá, porque no hay rol que las pierda.
class TablaLectura {
  static const remitos = 'remitos';
  static const remitoItems = 'remito_items';
  static const pagos = 'pagos';
  static const pagoMedios = 'pago_medios';
  static const notasCreditoDebito = 'notas_credito_debito';
  static const notasPedido = 'notas_pedido';
  static const notaPedidoItems = 'nota_pedido_items';
  static const costosSemana = 'costos_semana';
  static const remitosEliminados = 'remitos_eliminados';
  static const pagosEliminados = 'pagos_eliminados';
  static const notasPedidoEliminadas = 'notas_pedido_eliminadas';
  static const proveedores = 'proveedores';
  static const cargas = 'cargas';
  static const cargaPagos = 'carga_pagos';
  static const depositoConfig = 'deposito_config';
  static const depositoMovimientos = 'deposito_movimientos';
}

/// Decide qué puede leer un rol, a partir de sus permisos.
///
/// Se construye con el set de permisos del rol y si es admin, así que no
/// depende de `Usuario` ni de nada que necesite una sesión.
class LecturaPermitida {
  final Set<String> permisos;
  final bool esAdmin;

  const LecturaPermitida({
    this.permisos = const {},
    this.esAdmin = false,
  });

  /// Sin usuario (todavía no entró, o entró por el login legacy y no tiene
  /// sesión de Supabase): no se puede dar nada por legible.
  static const nada = LecturaPermitida();

  /// Todo, para cuando RLS está apagado. Es el estado de hoy: mientras
  /// ninguna tabla tenga RLS encendido, la base no niega nada y el provider
  /// tiene que seguir trayendo todo como siempre.
  static const todo = LecturaPermitida(esAdmin: true);

  bool tiene(String permiso) => esAdmin || permisos.contains(permiso);

  /// **La regla del saldo.** Espejo de `puede_ver_saldo()` en SQL.
  ///
  /// `saldo = remitos − pagos ± notas`, así que todo permiso que abra una
  /// pantalla donde se vea un saldo tiene que dar lectura sobre las tres
  /// tablas. Los dos últimos no son obvios y son los que más importan:
  ///
  /// * `gestionar_clientes` → la pestaña Clientes muestra el saldo de cada
  ///   cliente en pesos (`clientes_screen.dart`).
  /// * `gestionar_vendedores` → la pestaña Vendedores, el de cada vendedor.
  ///
  /// Con los cuatro roles que existen hoy esos dos arms no cambian nada,
  /// porque los tres roles que llegan a esas pestañas tienen además
  /// `ver_consultas`. Están por los roles que el admin **puede** armar desde
  /// Gestión de Usuarios.
  bool get puedeVerSaldo =>
      tiene('ver_consultas') ||
      tiene('crear_pago') ||
      tiene('gestionar_clientes') ||
      tiene('gestionar_vendedores');

  /// ¿Puede leer esta tabla?
  ///
  /// Una tabla que no esté en la lista devuelve **true**: son las abiertas a
  /// cualquier usuario activo. Preferir el lado permisivo acá es correcto —
  /// el que niega de verdad es Postgres, y este archivo solo evita preguntar
  /// de más y detecta el vacío engañoso.
  bool puedeLeer(String tabla) => switch (tabla) {
        TablaLectura.remitos ||
        TablaLectura.remitoItems =>
          puedeVerSaldo || tiene('crear_remito'),
        TablaLectura.pagos ||
        TablaLectura.pagoMedios ||
        TablaLectura.notasCreditoDebito =>
          puedeVerSaldo,
        TablaLectura.notasPedido || TablaLectura.notaPedidoItems => tiene(
              'ver_consultas',
            ) ||
            tiene('crear_remito') ||
            tiene('confirmar_remito'),
        TablaLectura.costosSemana => tiene('gestionar_costos'),
        TablaLectura.remitosEliminados ||
        TablaLectura.pagosEliminados ||
        TablaLectura.notasPedidoEliminadas =>
          tiene('ver_consultas'),
        TablaLectura.proveedores ||
        TablaLectura.cargas ||
        TablaLectura.cargaPagos =>
          tiene('gestionar_proveedores'),
        TablaLectura.depositoConfig || TablaLectura.depositoMovimientos =>
          tiene('gestionar_deposito'),
        _ => true,
      };

  /// **Si el saldo que calcula el provider se puede mostrar.**
  ///
  /// El saldo sale de tres tablas; si falta una, el número no es "incompleto",
  /// es **más alto que el real**, y un saldo más alto del real es lo que hace
  /// que alguien salga a cobrar plata que ya cobró. Cuando esto da false, la
  /// pantalla tiene que decir "no disponible" y no un número — mismo criterio
  /// que `mediasSinPesar` en el depósito: un número que parece exacto y no lo
  /// es, es peor que no mostrarlo.
  bool get saldosConfiables =>
      puedeLeer(TablaLectura.remitos) &&
      puedeLeer(TablaLectura.pagos) &&
      puedeLeer(TablaLectura.notasCreditoDebito);

  /// Las tablas de [tablas] que este rol **no** puede leer. El provider las
  /// guarda para poder contestar "no disponible" en vez de "sin datos".
  Set<String> noLegiblesDe(Iterable<String> tablas) =>
      tablas.where((t) => !puedeLeer(t)).toSet();
}
