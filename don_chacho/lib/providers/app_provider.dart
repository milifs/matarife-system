// ============================================================
// PROVIDER PRINCIPAL - Estado global de la app
// ============================================================
// Usa ChangeNotifier (Provider) para gestión de estado.
// Centraliza la carga de datos y notifica a la UI.
// ============================================================

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/database_service.dart';

class AppProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  // ── Estado ──
  List<Vendedor> _vendedores = [];
  List<Cliente> _clientes = [];
  List<Remito> _remitos = [];
  List<Pago> _pagos = [];
  List<NotaPedido> _notasPedido = [];
  List<NotaCreditoDebito> _notasCD = [];
  List<PagoEliminado> _pagosEliminados = [];
  List<RemitoEliminado> _remitosEliminados = [];
  List<NotaPedidoEliminada> _notasPedidoEliminadas = [];
  CostoSemanal? _costoSemanaActual;
  bool _loading = false;
  String? _error;

  // Usuario logueado
  Usuario? _usuarioActual;
  Usuario? get usuarioActual => _usuarioActual;

  void setUsuario(Usuario usuario) {
    _usuarioActual = usuario;
    notifyListeners();
  }

  /// Verifica si el usuario actual tiene un permiso
  bool tienePermiso(String permisoId) =>
      _usuarioActual?.tienePermiso(permisoId) ?? false;

  bool get esAdmin => _usuarioActual?.esAdmin ?? false;

  // Cache de saldos para evitar recalcular en cada build
  final Map<String, double> _saldosClientes = {};
  final Map<String, double> _saldosVendedores = {};

  // Cache de items de remito por remito_id (para kg por tipo)
  final Map<String, List<RemitoItem>> _remitoItems = {};

  // ── Getters ──
  List<Vendedor> get vendedores => _vendedores;
  List<Cliente> get clientes => _clientes;
  List<Remito> get remitos => _remitos;
  List<Pago> get pagos => _pagos;
  List<NotaPedido> get notasPedido => _notasPedido;
  List<NotaCreditoDebito> get notasCreditoDebito => _notasCD;
  List<PagoEliminado> get pagosEliminados => _pagosEliminados;
  List<RemitoEliminado> get remitosEliminados => _remitosEliminados;
  List<NotaPedidoEliminada> get notasPedidoEliminadas =>
      _notasPedidoEliminadas;
  List<NotaPedido> get notasPedidoPendientes =>
      _notasPedido.where((n) => n.esPendiente).toList();
  CostoSemanal? get costoSemanaActual => _costoSemanaActual;
  bool get loading => _loading;
  String? get error => _error;

  double getSaldoCliente(String clienteId) =>
      _saldosClientes[clienteId] ?? 0;
  double getSaldoVendedor(String vendedorId) =>
      _saldosVendedores[vendedorId] ?? 0;

  /// Total de saldo pendiente de cobro (todos los clientes)
  double get saldoTotal =>
      _saldosClientes.values.fold(0, (sum, s) => sum + s);

  /// Clientes de un vendedor
  List<Cliente> clientesDeVendedor(String vendedorId) =>
      _clientes.where((c) => c.vendedorId == vendedorId).toList();

  /// Vendedor por ID
  Vendedor? vendedorPorId(String id) {
    try {
      return _vendedores.firstWhere((v) => v.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Cliente por ID
  Cliente? clientePorId(String id) {
    try {
      return _clientes.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // CARGA INICIAL
  // ═══════════════════════════════════════════

  Future<void> cargarDatos() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Carga de datos en paralelo para reducir el tiempo de espera inicial
      final results = await Future.wait([
        _db.getVendedores(),
        _db.getClientes(),
        _db.getRemitos(),
        _db.getPagos(),
        _db.getPagosEliminados(),
        _db.getRemitoEliminados(),
        _db.getNotasPedido(),
        _db.getNotasPedidoEliminadas(),
        _db.getCostoSemana(DateTime.now()),
        _db.getAllCostosSemana(),
        _db.getNotasCreditoDebito(),
      ]);
      _vendedores = results[0] as List<Vendedor>;
      _clientes = results[1] as List<Cliente>;
      _remitos = results[2] as List<Remito>;
      _pagos = results[3] as List<Pago>;
      _pagosEliminados = results[4] as List<PagoEliminado>;
      _remitosEliminados = results[5] as List<RemitoEliminado>;
      _notasPedido = results[6] as List<NotaPedido>;
      _notasPedidoEliminadas = results[7] as List<NotaPedidoEliminada>;
      _costoSemanaActual = results[8] as CostoSemanal?;
      _costosSemanales = results[9] as List<CostoSemanal>;
      _notasCD = results[10] as List<NotaCreditoDebito>;

      // Items de remito en una sola query, agrupados en memoria
      _remitoItems.clear();
      final allItems = await _db.getAllRemitoItems();
      for (final item in allItems) {
        _remitoItems.putIfAbsent(item.remitoId, () => []).add(item);
      }

      // Calcular saldos
      await _recalcularSaldos();

      _loading = false;
      notifyListeners();
    } catch (e) {
      _loading = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _recalcularSaldos() async {
    _saldosClientes.clear();
    _saldosVendedores.clear();

    for (final cliente in _clientes) {
      // Solo remitos CONFIRMADOS cuentan para el saldo
      final totalRemitos = _remitos
          .where((r) => r.clienteId == cliente.id && r.esConfirmado)
          .fold<double>(0, (sum, r) => sum + r.totalPesos);
      final totalPagos = _pagos
          .where((p) => p.clienteId == cliente.id)
          .fold<double>(0, (sum, p) => sum + p.montoTotal);
      // Notas de débito suman al saldo; notas de crédito lo restan.
      final totalDebitos = _notasCD
          .where((n) => n.clienteId == cliente.id && n.esDebito)
          .fold<double>(0, (sum, n) => sum + n.monto);
      final totalCreditos = _notasCD
          .where((n) => n.clienteId == cliente.id && n.esCredito)
          .fold<double>(0, (sum, n) => sum + n.monto);
      _saldosClientes[cliente.id] =
          totalRemitos + totalDebitos - totalPagos - totalCreditos;
    }

    for (final vendedor in _vendedores) {
      final clientesDelVendedor =
          _clientes.where((c) => c.vendedorId == vendedor.id);
      _saldosVendedores[vendedor.id] = clientesDelVendedor.fold<double>(
          0, (sum, c) => sum + (_saldosClientes[c.id] ?? 0));
    }
  }

  // ═══════════════════════════════════════════
  // VENDEDORES CRUD
  // ═══════════════════════════════════════════

  Future<void> agregarVendedor(Vendedor vendedor) async {
    try {
      final nuevo = await _db.insertVendedor(vendedor);
      _vendedores.add(nuevo);
      notifyListeners();
    } catch (e) {
      _error = 'Error al agregar vendedor: $e';
      notifyListeners();
    }
  }

  Future<void> editarVendedor(Vendedor vendedor) async {
    try {
      await _db.updateVendedor(vendedor);
      final idx = _vendedores.indexWhere((v) => v.id == vendedor.id);
      if (idx != -1) _vendedores[idx] = vendedor;
      notifyListeners();
    } catch (e) {
      _error = 'Error al editar vendedor: $e';
      notifyListeners();
    }
  }

  Future<void> eliminarVendedor(String id) async {
    try {
      // Incluye clientes desactivados (soft-delete): siguen apuntando al
      // vendedor por FK, así que hay que avisar en vez de fallar con el
      // error crudo de Postgres.
      final cantClientes = await _db.contarClientesDeVendedor(id);
      if (cantClientes > 0) {
        final activos = clientesDeVendedor(id).length;
        final desactivados = cantClientes - activos;
        final detalle = desactivados > 0
            ? '$cantClientes cliente(s) vinculado(s) ($desactivados desactivado(s) que no se ven en la lista).'
            : '$cantClientes cliente(s) vinculado(s).';
        _error = 'No se puede eliminar el vendedor: tiene $detalle '
            'Reasigná esos clientes a otro vendedor antes de borrarlo.';
        notifyListeners();
        return;
      }
      await _db.deleteVendedor(id);
      _vendedores.removeWhere((v) => v.id == id);
      notifyListeners();
    } catch (e) {
      _error = 'Error al eliminar vendedor: $e';
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════
  // CLIENTES CRUD
  // ═══════════════════════════════════════════

  Future<void> agregarCliente(Cliente cliente) async {
    try {
      final nuevo = await _db.insertCliente(cliente);
      _clientes.add(nuevo);
      _saldosClientes[nuevo.id] = 0;
      notifyListeners();
    } catch (e) {
      _error = 'Error al agregar cliente: $e';
      notifyListeners();
    }
  }

  Future<void> editarCliente(Cliente cliente) async {
    try {
      await _db.updateCliente(cliente);
      final idx = _clientes.indexWhere((c) => c.id == cliente.id);
      if (idx != -1) _clientes[idx] = cliente;
      notifyListeners();
    } catch (e) {
      _error = 'Error al editar cliente: $e';
      notifyListeners();
    }
  }

  Future<void> eliminarCliente(String id) async {
    try {
      await _db.deleteCliente(id);
      _clientes.removeWhere((c) => c.id == id);
      _saldosClientes.remove(id);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al eliminar cliente: $e';
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════
  // REMITOS
  // ═══════════════════════════════════════════

  /// Devuelve los items (filas) de un remito ya cargado en memoria
  List<RemitoItem> itemsDeRemito(String remitoId) {
    return _remitoItems[remitoId] ?? [];
  }

  Future<void> agregarRemito(Remito remito, List<RemitoItem> items) async {
    try {
      // Asignar número secuencial
      final maxNumero = _remitos.isEmpty
          ? 0
          : _remitos.map((r) => r.numero).reduce((a, b) => a > b ? a : b);
      remito.numero = maxNumero + 1;

      final nuevo = await _db.insertRemito(remito, items);
      _remitos.insert(0, nuevo);

      // Cargar items del nuevo remito
      _remitoItems[nuevo.id] = await _db.getRemitoItems(nuevo.id);

      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al agregar remito: $e';
      notifyListeners();
    }
  }

  Future<void> actualizarRemito(
      Remito remito, List<RemitoItem> items) async {
    try {
      final actualizado = await _db.updateRemito(remito, items);
      final idx = _remitos.indexWhere((r) => r.id == remito.id);
      if (idx >= 0) {
        _remitos[idx] = actualizado;
      }
      _remitoItems[remito.id] = await _db.getRemitoItems(remito.id);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar remito: $e';
      notifyListeners();
    }
  }

  Future<void> eliminarRemito(String remitoId,
      {String? observacion, String? eliminadoPor}) async {
    try {
      final remito = _remitos.firstWhere((r) => r.id == remitoId);
      final re = RemitoEliminado(
        remitoId: remitoId,
        clienteId: remito.clienteId,
        fecha: remito.fecha,
        numero: remito.numero,
        totalKg: remito.totalKg,
        totalPesos: remito.totalPesos,
        observacion: observacion,
        eliminadoPor: eliminadoPor,
      );
      // Auditoría best-effort: si la columna observacion aún no existe
      // (migración no corrida) no debe impedir la eliminación.
      try {
        await _db.insertRemitoEliminado(re);
        _remitosEliminados.insert(0, re);
      } catch (_) {}
      await _db.deleteRemito(remitoId);
      _remitos.removeWhere((r) => r.id == remitoId);
      _remitoItems.remove(remitoId);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al eliminar remito: $e';
      notifyListeners();
    }
  }

  Future<void> confirmarRemito(
      String remitoId, String confirmadoPorId) async {
    try {
      await _db.cambiarEstadoRemito(
        remitoId: remitoId,
        estado: 'confirmado',
        confirmadoPor: confirmadoPorId,
      );
      final idx = _remitos.indexWhere((r) => r.id == remitoId);
      if (idx >= 0) {
        _remitos[idx].estado = 'confirmado';
        _remitos[idx].confirmadoPor = confirmadoPorId;
        _remitos[idx].confirmadoEn = DateTime.now();
      }
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al confirmar remito: $e';
      notifyListeners();
    }
  }

  Future<void> rechazarRemito(
      String remitoId, String confirmadoPorId, String? motivo) async {
    try {
      await _db.cambiarEstadoRemito(
        remitoId: remitoId,
        estado: 'rechazado',
        confirmadoPor: confirmadoPorId,
        motivo: motivo,
      );
      final idx = _remitos.indexWhere((r) => r.id == remitoId);
      if (idx >= 0) {
        _remitos[idx].estado = 'rechazado';
        _remitos[idx].confirmadoPor = confirmadoPorId;
        _remitos[idx].motivoRechazo = motivo;
      }
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al rechazar remito: $e';
      notifyListeners();
    }
  }

  /// Remitos confirmados (los que cuentan para saldos)
  List<Remito> get remitosConfirmados =>
      _remitos.where((r) => r.esConfirmado).toList();

  // ═══════════════════════════════════════════
  // PAGOS
  // ═══════════════════════════════════════════

  Future<void> agregarPago(Pago pago, List<PagoMedio> medios) async {
    try {
      // Asignar número secuencial
      final maxNumero = _pagos.isEmpty
          ? 0
          : _pagos.map((p) => p.numero).reduce((a, b) => a > b ? a : b);
      pago.numero = maxNumero + 1;

      final nuevo = await _db.insertPago(pago, medios);
      _pagos.insert(0, nuevo);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al registrar pago: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> actualizarPago(Pago pago, List<PagoMedio> medios) async {
    try {
      final actualizado = await _db.updatePago(pago, medios);
      final idx = _pagos.indexWhere((p) => p.id == pago.id);
      if (idx >= 0) {
        _pagos[idx] = actualizado;
      }
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar pago: $e';
      notifyListeners();
    }
  }

  Future<void> eliminarPago(String pagoId,
      {String? observacion, String? eliminadoPor}) async {
    try {
      final pago = _pagos.firstWhere((p) => p.id == pagoId);
      final medios = await _db.getPagoMedios(pagoId);
      final mediosJson = medios
          .map((m) => {'medio': m.medio.name, 'monto': m.monto})
          .toList();
      final pe = PagoEliminado(
        pagoId: pagoId,
        clienteId: pago.clienteId,
        fecha: pago.fecha,
        numero: pago.numero,
        montoTotal: pago.montoTotal,
        medios: mediosJson,
        observacion: observacion,
        eliminadoPor: eliminadoPor,
      );
      await _db.insertPagoEliminado(pe);
      _pagosEliminados.insert(0, pe);
      await _db.deletePago(pagoId);
      _pagos.removeWhere((p) => p.id == pagoId);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al eliminar pago: $e';
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════
  // NOTAS DE CRÉDITO / DÉBITO
  // ═══════════════════════════════════════════

  Future<void> agregarNotaCreditoDebito(NotaCreditoDebito nota) async {
    try {
      // Número secuencial separado por tipo (NC-XXXX / ND-XXXX)
      final delTipo = _notasCD.where((n) => n.tipo == nota.tipo);
      final maxNumero = delTipo.isEmpty
          ? 0
          : delTipo.map((n) => n.numero).reduce((a, b) => a > b ? a : b);
      nota.numero = maxNumero + 1;

      final nueva = await _db.insertNotaCreditoDebito(nota);
      _notasCD.insert(0, nueva);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al registrar nota: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> eliminarNotaCreditoDebito(String notaId,
      {String? eliminadoPor}) async {
    try {
      final nota = _notasCD.firstWhere((n) => n.id == notaId);
      await _db.deleteNotaCreditoDebito(nota, eliminadoPor: eliminadoPor);
      _notasCD.removeWhere((n) => n.id == notaId);
      await _recalcularSaldos();
      notifyListeners();
    } catch (e) {
      _error = 'Error al eliminar nota: $e';
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════
  // COSTO SEMANAL
  // ═══════════════════════════════════════════

  // ═══════════════════════════════════════════
  // PROVEEDORES Y CARGAS (compra de animales vivos)
  // ═══════════════════════════════════════════
  // Se cargan bajo demanda al entrar al módulo (igual que los costos
  // semanales) y no en cargarDatos(), para no demorar el login de la
  // secretaria y el cobrador, que no tienen acceso a este módulo.

  List<Proveedor> _proveedores = [];
  List<Carga> _cargas = [];
  List<CargaPago> _cargaPagos = [];
  bool _proveedoresCargados = false;

  List<Proveedor> get proveedores => _proveedores;
  List<Proveedor> get proveedoresActivos =>
      _proveedores.where((p) => p.activo).toList();
  List<Carga> get cargas => _cargas;
  bool get proveedoresCargados => _proveedoresCargados;

  Proveedor? proveedorPorId(String id) {
    try {
      return _proveedores.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  String nombreProveedor(String id) =>
      proveedorPorId(id)?.nombre ?? 'Proveedor eliminado';

  Carga? cargaPorId(String id) {
    try {
      return _cargas.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> cargarProveedores({bool forzar = false}) async {
    if (_proveedoresCargados && !forzar) return;
    try {
      final results = await Future.wait([
        _db.getProveedores(),
        _db.getCargas(),
        _db.getCargaPagos(),
      ]);
      _proveedores = results[0] as List<Proveedor>;
      _cargas = results[1] as List<Carga>;
      _cargaPagos = results[2] as List<CargaPago>;
      _proveedoresCargados = true;
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar proveedores: $e';
      notifyListeners();
    }
  }

  /// Pagos de una carga, del más viejo al más nuevo (como el Excel)
  List<CargaPago> pagosDeCarga(String cargaId) {
    final lista = _cargaPagos.where((p) => p.cargaId == cargaId).toList();
    lista.sort((a, b) {
      final porFecha = a.fecha.compareTo(b.fecha);
      return porFecha != 0 ? porFecha : a.creadoEn.compareTo(b.creadoEn);
    });
    return lista;
  }

  double totalPagadoCarga(String cargaId) =>
      pagosDeCarga(cargaId).fold<double>(0, (s, p) => s + p.monto);

  /// Cargas de un proveedor en orden cronológico (de la más vieja a la más
  /// nueva). Es el orden en que se encadena el saldo.
  List<Carga> cargasDeProveedor(String proveedorId) {
    final lista =
        _cargas.where((c) => c.proveedorId == proveedorId).toList();
    lista.sort((a, b) {
      final porFecha = a.fecha.compareTo(b.fecha);
      return porFecha != 0 ? porFecha : a.creadoEn.compareTo(b.creadoEn);
    });
    return lista;
  }

  /// Saldo que viene arrastrado de la carga ANTERIOR del mismo proveedor.
  /// Negativo = se le debe al proveedor; positivo = saldo a favor de Joaco.
  ///
  /// No se guarda en la base a propósito: se recalcula en cadena cada vez.
  /// Así, si se corrige una carga vieja o se agrega un pago atrasado, todas
  /// las cargas siguientes de ese proveedor se reacomodan solas.
  double saldoAnteriorDeCarga(Carga carga) {
    final lista = cargasDeProveedor(carga.proveedorId);
    var saldo = 0.0;
    for (final c in lista) {
      if (c.id == carga.id) break;
      saldo += totalPagadoCarga(c.id) - c.totalAPagar;
    }
    return saldo;
  }

  /// Saldo con el que cierra la carga = arrastre + pagos - total a pagar
  double saldoDeCarga(Carga carga) =>
      saldoAnteriorDeCarga(carga) + totalPagadoCarga(carga.id) - carga.totalAPagar;

  /// Saldo actual del proveedor (el de su última carga)
  double saldoProveedor(String proveedorId) {
    final lista = cargasDeProveedor(proveedorId);
    if (lista.isEmpty) return 0;
    return saldoDeCarga(lista.last);
  }

  /// Total que se le debe hoy a todos los proveedores (en positivo)
  double get deudaTotalProveedores {
    var total = 0.0;
    for (final p in _proveedores) {
      final saldo = saldoProveedor(p.id);
      if (saldo < 0) total += -saldo;
    }
    return total;
  }

  // ── ABM de proveedores ──

  Future<bool> guardarProveedor(Proveedor proveedor, {bool esNuevo = false}) async {
    try {
      if (esNuevo) {
        final creado = await _db.insertProveedor(proveedor);
        _proveedores.add(creado);
      } else {
        await _db.updateProveedor(proveedor);
        final i = _proveedores.indexWhere((p) => p.id == proveedor.id);
        if (i >= 0) _proveedores[i] = proveedor;
      }
      _proveedores.sort((a, b) => a.nombre.compareTo(b.nombre));
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al guardar proveedor: $e';
      notifyListeners();
      return false;
    }
  }

  /// Borra el proveedor solo si no tiene cargas. Si tiene historia hay que
  /// desactivarlo, para no dejar cargas huérfanas sin nombre.
  Future<String?> eliminarProveedor(String id) async {
    try {
      final cargas = await _db.contarCargasDeProveedor(id);
      if (cargas > 0) {
        return 'El proveedor tiene $cargas carga(s) registradas. '
            'Desactivalo en vez de borrarlo.';
      }
      await _db.deleteProveedor(id);
      _proveedores.removeWhere((p) => p.id == id);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Error al eliminar proveedor: $e';
    }
  }

  // ── ABM de cargas ──

  Future<Carga?> crearCarga(Carga carga) async {
    try {
      final creada = await _db.insertCarga(carga);
      _cargas.insert(0, creada);
      notifyListeners();
      return creada;
    } catch (e) {
      _error = 'Error al crear la carga: $e';
      notifyListeners();
      return null;
    }
  }

  Future<Carga?> actualizarCarga(Carga carga) async {
    try {
      final actualizada = await _db.updateCarga(carga);
      final i = _cargas.indexWhere((c) => c.id == carga.id);
      if (i >= 0) _cargas[i] = actualizada;
      notifyListeners();
      return actualizada;
    } catch (e) {
      _error = 'Error al actualizar la carga: $e';
      notifyListeners();
      return null;
    }
  }

  /// Elimina la carga y sus pagos. Antes de borrar deja la fila de auditoría
  /// con la observación y una copia de los pagos que se van en cascada.
  Future<bool> eliminarCarga(Carga carga, String observacion) async {
    try {
      final pagos = pagosDeCarga(carga.id);
      await _db.insertCargaEliminada(CargaEliminada(
        cargaId: carga.id,
        numero: carga.numero,
        proveedorId: carga.proveedorId,
        proveedorNombre: nombreProveedor(carga.proveedorId),
        fecha: carga.fecha,
        cantidadAnimales: carga.cantidadAnimales,
        kgVivo: carga.kgVivo,
        kgMediaRes: carga.kgMediaRes,
        totalAPagar: carga.totalAPagar,
        totalPagado: totalPagadoCarga(carga.id),
        pagos: pagos
            .map((p) => {
                  'fecha': p.fecha.toIso8601String(),
                  'medio': p.medio,
                  'monto': p.monto,
                })
            .toList(),
        observacion: observacion,
        eliminadoPor: _usuarioActual?.nombreCompleto,
      ));
      await _db.deleteCarga(carga.id);
      _cargas.removeWhere((c) => c.id == carga.id);
      _cargaPagos.removeWhere((p) => p.cargaId == carga.id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al eliminar la carga: $e';
      notifyListeners();
      return false;
    }
  }

  // ── Pagos a proveedores ──

  Future<bool> guardarPagoCarga(CargaPago pago, {bool esNuevo = false}) async {
    try {
      if (esNuevo) {
        final creado = await _db.insertCargaPago(pago);
        _cargaPagos.add(creado);
      } else {
        final actualizado = await _db.updateCargaPago(pago);
        final i = _cargaPagos.indexWhere((p) => p.id == pago.id);
        if (i >= 0) _cargaPagos[i] = actualizado;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al guardar el pago: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> eliminarPagoCarga(CargaPago pago, String observacion) async {
    try {
      final carga = cargaPorId(pago.cargaId);
      await _db.insertCargaPagoEliminado(CargaPagoEliminado(
        pagoId: pago.id,
        cargaId: pago.cargaId,
        cargaNumero: carga?.numero ?? 0,
        proveedorNombre:
            carga == null ? '' : nombreProveedor(carga.proveedorId),
        fecha: pago.fecha,
        medio: pago.medio,
        monto: pago.monto,
        observacion: observacion,
        eliminadoPor: _usuarioActual?.nombreCompleto,
      ));
      await _db.deleteCargaPago(pago.id);
      _cargaPagos.removeWhere((p) => p.id == pago.id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al eliminar el pago: $e';
      notifyListeners();
      return false;
    }
  }

  List<CostoSemanal> _costosSemanales = [];
  List<CostoSemanal> get costosSemanales => _costosSemanales;

  Future<void> cargarCostosSemanales() async {
    try {
      _costosSemanales = await _db.getAllCostosSemana();
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar costos: $e';
      notifyListeners();
    }
  }

  Future<void> guardarCostoSemana(CostoSemanal costo) async {
    try {
      _costoSemanaActual = await _db.insertCostoSemana(costo);
      // Recargar la lista completa
      _costosSemanales = await _db.getAllCostosSemana();
      notifyListeners();
    } catch (e) {
      _error = 'Error al guardar costo: $e';
      notifyListeners();
    }
  }

  /// Busca el costo que corresponde a una fecha dada (el de la semana de esa fecha)
  CostoSemanal? costoParaFecha(DateTime fecha) {
    final lunes = fecha.subtract(Duration(days: fecha.weekday - 1));
    final lunesNorm = DateTime(lunes.year, lunes.month, lunes.day);
    try {
      return _costosSemanales.firstWhere((c) {
        final cLunes = DateTime(
            c.semanaInicio.year, c.semanaInicio.month, c.semanaInicio.day);
        return cLunes.isAtSameMomentAs(lunesNorm);
      });
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════
  // UTILIDADES PARA CONSULTAS
  // ═══════════════════════════════════════════

  /// Buckets de deuda de un cliente (FIFO): remitos confirmados + notas de
  /// débito, ordenados por fecha. Los créditos (pagos + notas de crédito) se
  /// aplican del más viejo al más nuevo. Cada bucket queda con su deuda
  /// pendiente y su fecha de vencimiento (fecha + plazo del cliente).
  List<DeudaBucket> bucketsDeudaCliente(Cliente cliente) {
    final buckets = <DeudaBucket>[];
    for (final r in _remitos
        .where((r) => r.clienteId == cliente.id && r.esConfirmado)) {
      buckets.add(DeudaBucket(
        fecha: r.fecha,
        orden: r.numero,
        vencimiento: r.fecha.add(Duration(days: cliente.plazoPagoDias)),
        remito: r,
        deuda: r.totalPesos,
      ));
    }
    for (final n in _notasCD
        .where((n) => n.clienteId == cliente.id && n.esDebito)) {
      buckets.add(DeudaBucket(
        fecha: n.fecha,
        orden: n.numero,
        vencimiento: n.fecha.add(Duration(days: cliente.plazoPagoDias)),
        notaDebito: n,
        deuda: n.monto,
      ));
    }
    buckets.sort((a, b) {
      final cmp = a.fecha.compareTo(b.fecha);
      return cmp != 0 ? cmp : a.orden.compareTo(b.orden);
    });

    // Créditos que reducen deuda FIFO: pagos + notas de crédito
    double creditos = _pagos
            .where((p) => p.clienteId == cliente.id)
            .fold<double>(0, (s, p) => s + p.montoTotal) +
        _notasCD
            .where((n) => n.clienteId == cliente.id && n.esCredito)
            .fold<double>(0, (s, n) => s + n.monto);

    for (final b in buckets) {
      if (creditos >= b.deuda) {
        creditos -= b.deuda;
        b.deuda = 0;
      } else {
        b.deuda -= creditos;
        creditos = 0;
      }
    }
    return buckets;
  }

  Cliente _clientePorIdOrEmpty(String clienteId) => _clientes.firstWhere(
        (c) => c.id == clienteId,
        orElse: () => Cliente(
            nombreRazonSocial: '',
            telefono: '',
            vendedorId: '',
            plazoPagoDias: 0),
      );

  /// Clientes con saldo vencido
  List<Map<String, dynamic>> clientesConSaldoVencido() {
    final resultado = <Map<String, dynamic>>[];
    final ahora = DateTime.now();
    for (final cliente in _clientes) {
      final saldo = _saldosClientes[cliente.id] ?? 0;
      if (saldo <= 0) continue;

      // Primer bucket con deuda pendiente (el más viejo)
      DeudaBucket? primero;
      for (final b in bucketsDeudaCliente(cliente)) {
        if (b.deuda > 0) {
          primero = b;
          break;
        }
      }
      if (primero == null) continue;

      final diasVencido = ahora.difference(primero.vencimiento).inDays;
      if (diasVencido > 0) {
        resultado.add({
          'cliente': cliente,
          'saldo': saldo,
          'diasVencido': diasVencido,
          'vendedor': vendedorPorId(cliente.vendedorId),
        });
      }
    }

    resultado.sort((a, b) =>
        (b['diasVencido'] as int).compareTo(a['diasVencido'] as int));
    return resultado;
  }

  /// Cantidad de clientes vencidos por vendedor
  int clientesVencidosDeVendedor(String vendedorId) {
    return clientesConSaldoVencido()
        .where((m) => (m['cliente'] as Cliente).vendedorId == vendedorId)
        .length;
  }

  /// Todos los cargos (remitos + notas de débito) con deuda vencida (FIFO),
  /// ordenados por días vencido desc. Cada entrada trae 'remito' o 'nota'.
  List<Map<String, dynamic>> todosRemitosVencidos() {
    final resultado = <Map<String, dynamic>>[];
    final ahora = DateTime.now();

    for (final cliente in _clientes) {
      final saldo = _saldosClientes[cliente.id] ?? 0;
      if (saldo <= 0) continue;

      for (final b in bucketsDeudaCliente(cliente)) {
        if (b.deuda <= 0) continue;
        final diasVencido = ahora.difference(b.vencimiento).inDays;
        if (diasVencido > 0) {
          resultado.add({
            if (b.remito != null) 'remito': b.remito,
            if (b.notaDebito != null) 'nota': b.notaDebito,
            'cliente': cliente,
            'vendedor': vendedorPorId(cliente.vendedorId),
            'diasVencido': diasVencido,
            'deuda': b.deuda,
          });
        }
      }
    }

    resultado.sort((a, b) =>
        (b['diasVencido'] as int).compareTo(a['diasVencido'] as int));
    return resultado;
  }

  /// Todos los cargos con deuda NO vencida (FIFO), ordenados por días restantes desc
  List<Map<String, dynamic>> todosRemitosNoVencidos() {
    final resultado = <Map<String, dynamic>>[];
    final ahora = DateTime.now();

    for (final cliente in _clientes) {
      final saldo = _saldosClientes[cliente.id] ?? 0;
      if (saldo <= 0) continue;

      for (final b in bucketsDeudaCliente(cliente)) {
        if (b.deuda <= 0) continue;
        final diasVencido = ahora.difference(b.vencimiento).inDays;
        if (diasVencido <= 0) {
          resultado.add({
            if (b.remito != null) 'remito': b.remito,
            if (b.notaDebito != null) 'nota': b.notaDebito,
            'cliente': cliente,
            'vendedor': vendedorPorId(cliente.vendedorId),
            'diasRestantes': -diasVencido,
            'deuda': b.deuda,
          });
        }
      }
    }

    resultado.sort((a, b) =>
        (b['diasRestantes'] as int).compareTo(a['diasRestantes'] as int));
    return resultado;
  }

  /// Cantidad de cargos con deuda vencida para un cliente (FIFO)
  int remitosVencidosCliente(String clienteId) {
    final cliente = _clientePorIdOrEmpty(clienteId);
    int vencidos = 0;
    final ahora = DateTime.now();
    for (final b in bucketsDeudaCliente(cliente)) {
      if (b.deuda > 0 && ahora.difference(b.vencimiento).inDays > 0) {
        vencidos++;
      }
    }
    return vencidos;
  }

  /// Monto total vencido para un cliente (FIFO)
  double saldoVencidoCliente(String clienteId) {
    final cliente = _clientePorIdOrEmpty(clienteId);
    double vencido = 0;
    final ahora = DateTime.now();
    for (final b in bucketsDeudaCliente(cliente)) {
      if (b.deuda > 0 && ahora.difference(b.vencimiento).inDays > 0) {
        vencido += b.deuda;
      }
    }
    return vencido;
  }

  DateTime _inicioSemana(DateTime ref) {
    final d = ref.subtract(Duration(days: ref.weekday - 1));
    return DateTime(d.year, d.month, d.day);
  }

  /// Kg vendidos en la semana de [semana] (default: semana actual)
  double kgVendidosSemana([DateTime? semana]) {
    final inicio = _inicioSemana(semana ?? DateTime.now());
    final fin = inicio.add(const Duration(days: 7));
    return _remitos
        .where((r) => r.esConfirmado && !r.fecha.isBefore(inicio) && r.fecha.isBefore(fin))
        .fold<double>(0, (sum, r) => sum + r.totalKg);
  }

  /// Kg vendidos en la semana por tipo de carne
  Map<String, double> kgVendidosSemanasPorTipo([DateTime? semana]) {
    final inicio = _inicioSemana(semana ?? DateTime.now());
    final fin = inicio.add(const Duration(days: 7));
    final remitosSemana = _remitos
        .where((r) => r.esConfirmado && !r.fecha.isBefore(inicio) && r.fecha.isBefore(fin));

    final resultado = <String, double>{};
    for (final remito in remitosSemana) {
      final items = _remitoItems[remito.id] ?? [];
      for (final item in items) {
        final tipo = _normalizarTipo(item.tipoCarne);
        resultado[tipo] = (resultado[tipo] ?? 0) + item.kgTotal;
      }
    }
    return resultado;
  }

  /// Cantidad de medias reses vendidas en la semana por tipo de carne
  Map<String, int> mediasVendidasSemanasPorTipo([DateTime? semana]) {
    final inicio = _inicioSemana(semana ?? DateTime.now());
    final fin = inicio.add(const Duration(days: 7));
    final remitosSemana = _remitos
        .where((r) => r.esConfirmado && !r.fecha.isBefore(inicio) && r.fecha.isBefore(fin));

    final resultado = <String, int>{};
    for (final remito in remitosSemana) {
      final items = _remitoItems[remito.id] ?? [];
      for (final item in items) {
        final tipo = _normalizarTipo(item.tipoCarne);
        resultado[tipo] = (resultado[tipo] ?? 0) + item.cantidadMedias;
      }
    }
    return resultado;
  }

  /// Venta en pesos por tipo de carne en la semana
  Map<String, double> ventaSemanasPorTipo([DateTime? semana]) {
    final inicio = _inicioSemana(semana ?? DateTime.now());
    final fin = inicio.add(const Duration(days: 7));
    final remitosSemana = _remitos
        .where((r) => r.esConfirmado && !r.fecha.isBefore(inicio) && r.fecha.isBefore(fin));

    final resultado = <String, double>{};
    for (final remito in remitosSemana) {
      final items = _remitoItems[remito.id] ?? [];
      for (final item in items) {
        final tipo = _normalizarTipo(item.tipoCarne);
        resultado[tipo] = (resultado[tipo] ?? 0) + item.subtotal;
      }
    }
    return resultado;
  }

  /// Ganancia semanal por tipo de carne
  Map<String, double> gananciaSemanalPorTipo([DateTime? semana]) {
    final s = semana ?? DateTime.now();
    final costo = costoParaFecha(s);
    if (costo == null) return {};
    final kgPorTipo = kgVendidosSemanasPorTipo(s);
    final ventaPorTipo = ventaSemanasPorTipo(s);
    final resultado = <String, double>{};

    for (final tipo in {...kgPorTipo.keys, ...ventaPorTipo.keys}) {
      final venta = ventaPorTipo[tipo] ?? 0;
      final kg = kgPorTipo[tipo] ?? 0;
      resultado[tipo] = venta - (kg * costo.costoPorTipo(tipo));
    }
    return resultado;
  }

  /// Descuento total por comisión de transferencias en los pagos de la semana de [semana]
  double descuentoTransferenciasSemana([DateTime? semana]) {
    final inicio = _inicioSemana(semana ?? DateTime.now());
    final fin = inicio.add(const Duration(days: 7));
    return _pagos
        .where((p) => !p.fecha.isBefore(inicio) && p.fecha.isBefore(fin))
        .fold<double>(0, (sum, p) => sum + (p.montoTotal - p.netoRecibido));
  }

  /// Descuento total por comisión de transferencias en los pagos de un rango de fechas
  double descuentoTransferenciasRango(DateTime desde, DateTime hasta) {
    return _pagos
        .where((p) => !p.fecha.isBefore(desde) && !p.fecha.isAfter(hasta))
        .fold<double>(0, (sum, p) => sum + (p.montoTotal - p.netoRecibido));
  }

  String _normalizarTipo(String tipo) {
    final t = tipo.toLowerCase().trim();
    if (t.contains('cerdo')) return 'Cerdo';
    // Novillo y todos sus cortes (pierna mocha/pistola, plancha de asado,
    // octavo, 1/4 delantero, ternera, vaquillona, etc.) computan como Novillo.
    return 'Novillo';
  }

  /// Total vendido en pesos en la semana actual
  double ventaSemana() {
    final lunes =
        DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
    final inicioSemana = DateTime(lunes.year, lunes.month, lunes.day);
    return _remitos
        .where((r) => r.fecha.isAfter(inicioSemana))
        .fold<double>(0, (sum, r) => sum + r.totalPesos);
  }

  /// Obtiene los medios de pago de un pago específico
  Future<List<PagoMedio>> getMediosDePago(String pagoId) async {
    return _db.getPagoMedios(pagoId);
  }

  // ═══════════════════════════════════════════
  // CIERRE DE JORNADA DEL COBRADOR (v19.2)
  // ═══════════════════════════════════════════

  /// Quiénes registraron pagos alguna vez, A→Z.
  ///
  /// Sale de los pagos, no de la tabla de usuarios: la lista es "quién cobró",
  /// así que incluye a los que ya no están activos y deja afuera a los que
  /// nunca cobraron. `registrado_por` guarda el nombre completo, de modo que
  /// si se le cambia el nombre a un usuario los pagos viejos quedan con el
  /// nombre viejo — por eso el filtro es por nombre y no por id.
  List<String> get cobradores {
    final nombres = _pagos
        .map((p) => (p.registradoPor ?? '').trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    nombres.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return nombres;
  }

  /// Los días en los que [cobrador] registró pagos, del más nuevo al más viejo.
  List<DateTime> diasConCobros(String cobrador) {
    final dias = _pagosDe(cobrador)
        .map((p) => DateTime(p.fecha.year, p.fecha.month, p.fecha.day))
        .toSet()
        .toList();
    dias.sort((a, b) => b.compareTo(a));
    return dias;
  }

  /// Resumen de lo que [cobrador] cobró el día [dia], con los medios de pago
  /// de todos los pagos traídos en una sola query.
  ///
  /// El día es el de `pago.fecha` (ver la nota en [ResumenJornada]).
  Future<ResumenJornada> resumenJornada({
    required String cobrador,
    required DateTime dia,
  }) async {
    final delDia = _pagosDe(cobrador)
        .where((p) =>
            p.fecha.year == dia.year &&
            p.fecha.month == dia.month &&
            p.fecha.day == dia.day)
        .toList();

    final medios =
        await _db.getMediosDePagos(delDia.map((p) => p.id).toList());

    return ResumenJornada(
      cobrador: cobrador,
      dia: dia,
      cobros: delDia.map((p) {
        final cliente = clientePorId(p.clienteId);
        return CobroJornada(
          pago: p,
          clienteNombre: cliente?.nombreRazonSocial ?? 'Cliente eliminado',
          vendedorNombre: cliente != null
              ? vendedorPorId(cliente.vendedorId)?.nombreCompleto
              : null,
          medios: medios[p.id] ?? const [],
        );
      }).toList(),
    );
  }

  Iterable<Pago> _pagosDe(String cobrador) {
    final buscado = cobrador.trim().toLowerCase();
    return _pagos.where(
        (p) => (p.registradoPor ?? '').trim().toLowerCase() == buscado);
  }

  void limpiarError() {
    _error = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  // NOTAS DE PEDIDO
  // ═══════════════════════════════════════════

  Future<void> agregarNotaPedido(
      NotaPedido ndp, List<NotaPedidoItem> items) async {
    try {
      final maxNumero = _notasPedido.isEmpty
          ? 0
          : _notasPedido.map((n) => n.numero).reduce((a, b) => a > b ? a : b);
      ndp.numero = maxNumero + 1;
      final nuevo = await _db.insertNotaPedido(ndp, items);
      _notasPedido.insert(0, nuevo);
      notifyListeners();
    } catch (e) {
      _error = 'Error al guardar nota de pedido: $e';
      notifyListeners();
    }
  }

  Future<void> actualizarNotaPedido(
      NotaPedido ndp, List<NotaPedidoItem> items) async {
    try {
      final actualizado = await _db.updateNotaPedido(ndp, items);
      final idx = _notasPedido.indexWhere((n) => n.id == ndp.id);
      if (idx >= 0) _notasPedido[idx] = actualizado;
      notifyListeners();
    } catch (e) {
      _error = 'Error al actualizar nota de pedido: $e';
      notifyListeners();
    }
  }

  Future<void> eliminarNotaPedido(String ndpId,
      {String? observacion, String? eliminadoPor}) async {
    try {
      final ndp = _notasPedido.firstWhere((n) => n.id == ndpId);
      final nombreCliente = ndp.clienteId != null
          ? clientePorId(ndp.clienteId!)?.nombreRazonSocial
          : ndp.clienteNombreLibre;
      final ne = NotaPedidoEliminada(
        notaPedidoId: ndpId,
        numero: ndp.numero,
        fecha: ndp.fecha,
        clienteId: ndp.clienteId,
        clienteNombre: nombreCliente,
        estado: ndp.estado,
        totalKg: ndp.totalKg,
        totalPesos: ndp.totalPesos,
        observacion: observacion,
        eliminadoPor: eliminadoPor,
      );
      // Auditoría best-effort: si la tabla aún no existe (migración no
      // corrida) no debe impedir la eliminación de la nota.
      try {
        await _db.insertNotaPedidoEliminada(ne);
        _notasPedidoEliminadas.insert(0, ne);
      } catch (_) {}
      await _db.deleteNotaPedido(ndpId);
      _notasPedido.removeWhere((n) => n.id == ndpId);
      notifyListeners();
    } catch (e) {
      _error = 'Error al eliminar nota de pedido: $e';
      notifyListeners();
    }
  }

  /// Confirma la NDP y crea el Remito correspondiente.
  Future<Remito?> confirmarNotaPedido(
      NotaPedido ndp, String clienteId, String confirmadoPorId) async {
    try {
      final maxNumero = _remitos.isEmpty
          ? 0
          : _remitos.map((r) => r.numero).reduce((a, b) => a > b ? a : b);
      final remito = await _db.confirmarNotaPedido(
        ndp: ndp,
        clienteId: clienteId,
        confirmadoPorId: confirmadoPorId,
        proximoNumeroRemito: maxNumero + 1,
      );

      // Actualizar estado en memoria
      final idx = _notasPedido.indexWhere((n) => n.id == ndp.id);
      if (idx >= 0) {
        _notasPedido[idx].estado = 'confirmado';
        _notasPedido[idx].confirmadoPor = confirmadoPorId;
        _notasPedido[idx].confirmadoEn = DateTime.now();
        _notasPedido[idx].remitoId = remito.id;
      }

      // Agregar remito a la lista y recalcular saldos
      _remitos.insert(0, remito);
      _remitoItems[remito.id] = await _db.getRemitoItems(remito.id);
      await _recalcularSaldos();
      notifyListeners();
      return remito;
    } catch (e) {
      _error = 'Error al confirmar nota de pedido: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> rechazarNotaPedido(
      String ndpId, String confirmadoPorId, String? motivo) async {
    try {
      await _db.cambiarEstadoNotaPedido(
        ndpId: ndpId,
        estado: 'rechazado',
        confirmadoPor: confirmadoPorId,
        motivo: motivo,
      );
      final idx = _notasPedido.indexWhere((n) => n.id == ndpId);
      if (idx >= 0) {
        _notasPedido[idx].estado = 'rechazado';
        _notasPedido[idx].confirmadoPor = confirmadoPorId;
        _notasPedido[idx].motivoRechazo = motivo;
      }
      notifyListeners();
    } catch (e) {
      _error = 'Error al rechazar nota de pedido: $e';
      notifyListeners();
    }
  }
  // DEPÓSITO (v19.5) — stock de medias reses
  // ═══════════════════════════════════════════
  // Existe porque desde la cámara sacaron dos medias para un cliente, la
  // cajera se olvidó de cargar el remito y nadie podía decir dónde estaban:
  // plata perdida. Cierra la ecuación entre lo comprado, lo distribuido a
  // clientes y lo guardado en depósito.
  //
  // NADA del stock se persiste: se deriva de cargas + remitos + movimientos,
  // igual que el saldo arrastrado del proveedor. Cargar un remito atrasado o
  // corregir uno viejo reacomoda todo solo, sin recalcular ni migrar nada.
  //
  // Depende de las cargas, así que `cargarDeposito` se asegura primero de que
  // los proveedores estén cargados (son lazy).

  DepositoConfig? _depositoConfig;
  List<DepositoMovimiento> _depositoMovimientos = [];
  bool _depositoCargado = false;

  DepositoConfig? get depositoConfig => _depositoConfig;
  List<DepositoMovimiento> get depositoMovimientos => _depositoMovimientos;
  bool get depositoCargado => _depositoCargado;

  /// true mientras el admin no haya fijado la fecha de arranque: sin eso no
  /// hay desde cuándo contar y la pantalla pide configurarlo.
  bool get depositoSinConfigurar => _depositoConfig == null;

  Future<void> cargarDeposito({bool forzar = false}) async {
    if (_depositoCargado && !forzar) return;
    try {
      // El stock sale de las cargas de proveedores, que son lazy.
      await cargarProveedores(forzar: forzar);
      final results = await Future.wait([
        _db.getDepositoConfig(),
        _db.getDepositoMovimientos(),
      ]);
      _depositoConfig = results[0] as DepositoConfig?;
      _depositoMovimientos = results[1] as List<DepositoMovimiento>;
      _depositoCargado = true;
      notifyListeners();
    } catch (e) {
      _error = 'Error al cargar el depósito: $e';
      notifyListeners();
    }
  }

  /// Fecha sin hora, para comparar contra `fecha_inicio` (que es un DATE).
  DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  /// El stock completo de un tipo ([Proveedor.tipoNovillo] / `tipoCerdo`),
  /// con todos los componentes desglosados y la comparación contra el último
  /// recuento físico. Devuelve un stock en cero si todavía no hay arranque.
  StockDeposito stockDeposito(String tipo) {
    if (_depositoConfig == null) return StockDeposito(tipo: tipo);

    final hoy = _componentesDeposito(tipo, null);
    final recuento = _ultimoRecuento(tipo);

    // El recuento se compara contra el teórico DE SU MOMENTO, no contra el de
    // hoy: si no, una compra posterior al último recuento aparecería como un
    // faltante gigante (se cuenta 10 el viernes, el lunes entra una carga de
    // 200 y el sistema gritaría "faltan 200 medias").
    final teoricoAlRecuento = recuento == null
        ? null
        : _componentesDeposito(tipo, recuento.creadoEn).teorico;

    return StockDeposito(
      tipo: tipo,
      inicial: hoy.inicial,
      compradas: hoy.compradas,
      entradas: hoy.entradas,
      remitidas: hoy.remitidas,
      salidasPendientes: hoy.salidasPendientes,
      salidasDefinitivas: hoy.salidasDefinitivas,
      recuento: recuento?.medias,
      fechaRecuento: recuento?.fecha,
      teoricoAlRecuento: teoricoAlRecuento,
      pendientes: hoy.pendientes,
    );
  }

  StockDeposito get stockNovillo => stockDeposito(Proveedor.tipoNovillo);
  StockDeposito get stockCerdo => stockDeposito(Proveedor.tipoCerdo);

  /// true si hay algo que mirar: medias que faltan en la cámara o salidas sin
  /// remito. Es el disparador del aviso en la pantalla del depósito.
  bool get hayAlertaDeposito {
    for (final s in [stockNovillo, stockCerdo]) {
      if (s.faltan || s.hayPendientes) return true;
    }
    return false;
  }

  /// Los componentes del stock de un tipo hasta un momento dado.
  ///
  /// [hasta] filtra por `creado_en` (cuándo se cargó en el sistema, no la
  /// fecha tipeada): null es "ahora". El recuento usa este corte para
  /// comparar contra el teórico que correspondía cuando se contó.
  ///
  /// Los campos de recuento del resultado van vacíos: acá solo se arman los
  /// componentes y el getter `teorico` ya los suma.
  StockDeposito _componentesDeposito(String tipo, DateTime? hasta) {
    final config = _depositoConfig!;
    final desde = _soloFecha(config.fechaInicio);
    bool yaEstaba(DateTime creadoEn) =>
        hasta == null || !creadoEn.isAfter(hasta);

    // ── Compras al proveedor: cada animal en pie son dos medias ──
    // El tipo lo decide el PROVEEDOR (novillo/cerdo), que es donde vive esa
    // información: a propósito no se congela en la carga.
    var compradas = 0.0;
    for (final carga in _cargas) {
      if (_soloFecha(carga.fecha).isBefore(desde)) continue;
      if (!yaEstaba(carga.creadoEn)) continue;
      final proveedor = proveedorPorId(carga.proveedorId);
      final tipoProveedor = proveedor?.tipo ?? Proveedor.tipoNovillo;
      if (tipoProveedor != tipo) continue;
      compradas += carga.cantidadAnimales * mediasPorAnimal;
    }

    // ── Medias distribuidas a clientes ──
    // Solo remitos CONFIRMADOS, igual que los saldos: una nota de pedido
    // pendiente no sacó carne de la cámara todavía.
    // Cada item se convierte por la tabla de equivalencias, porque el campo
    // "Medias" del formulario cuenta unidades del corte elegido: 3 piernas
    // son 1 media, no 3.
    var remitidas = 0.0;
    for (final remito in _remitos) {
      if (!remito.esConfirmado) continue;
      if (_soloFecha(remito.fecha).isBefore(desde)) continue;
      if (!yaEstaba(remito.creadoEn)) continue;
      for (final item in (_remitoItems[remito.id] ?? const <RemitoItem>[])) {
        if (stockDeTipoCarne(item.tipoCarne) != tipo) continue;
        remitidas +=
            item.cantidadMedias * equivalenciaEnMedias(item.tipoCarne);
      }
    }

    // ── Movimientos cargados a mano ──
    var entradas = 0.0;
    var salidasDefinitivas = 0.0;
    for (final mov in _depositoMovimientos) {
      if (mov.tipo != tipo) continue;
      if (_soloFecha(mov.fecha).isBefore(desde)) continue;
      if (!yaEstaba(mov.creadoEn)) continue;
      if (mov.esEntrada) entradas += mov.medias;
      if (mov.esSalidaDefinitiva) salidasDefinitivas += mov.medias;
    }

    final pendientes = _salidasPendientes(tipo, hasta);

    return StockDeposito(
      tipo: tipo,
      inicial: config.inicialDe(tipo),
      compradas: compradas,
      entradas: entradas,
      remitidas: remitidas,
      salidasPendientes: pendientes.medias,
      salidasDefinitivas: salidasDefinitivas,
      pendientes: pendientes.movimientos,
    );
  }

  /// Las salidas que todavía esperan su remito, cerrando por FIFO.
  ///
  /// Una salida se registra justamente porque el remito no está cargado
  /// todavía, así que la cierra cualquier remito de ese tipo cargado DESPUÉS
  /// de ella, y la salida más vieja se cierra primero. Las ventanas están
  /// anidadas (los remitos posteriores a una salida nueva son un subconjunto
  /// de los posteriores a una vieja), así que alcanza con descontar lo que ya
  /// consumieron las salidas anteriores.
  ///
  /// `medias` es el pendiente exacto, incluidas las salidas cubiertas a
  /// medias; `movimientos` son las salidas con algo todavía abierto.
  ({List<DepositoMovimiento> movimientos, double medias}) _salidasPendientes(
      String tipo, DateTime? hasta) {
    final config = _depositoConfig!;
    final desde = _soloFecha(config.fechaInicio);

    final salidas = _depositoMovimientos
        .where((m) =>
            m.tipo == tipo &&
            m.esSalidaPendienteDeRemito &&
            !_soloFecha(m.fecha).isBefore(desde) &&
            (hasta == null || !m.creadoEn.isAfter(hasta)))
        .toList()
      ..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));

    final abiertas = <DepositoMovimiento>[];
    var pendiente = 0.0;
    var consumido = 0.0; // medias de remito ya usadas por salidas anteriores

    for (final salida in salidas) {
      final disponible =
          _remitidasCargadasDespuesDe(tipo, salida.creadoEn, hasta) -
              consumido;
      if (disponible >= salida.medias - toleranciaMedias) {
        // Ya apareció el remito: la salida se cierra y deja de descontar
        // (ahora descuenta el remito, así que no se cuenta dos veces).
        consumido += salida.medias;
        continue;
      }
      final cubierto = disponible > 0 ? disponible : 0.0;
      consumido += cubierto;
      pendiente += salida.medias - cubierto;
      abiertas.add(salida);
    }

    return (movimientos: abiertas, medias: pendiente);
  }

  /// Medias remitidas de un tipo cargadas al sistema después de [creadoEn].
  double _remitidasCargadasDespuesDe(
      String tipo, DateTime creadoEn, DateTime? hasta) {
    final desde = _soloFecha(_depositoConfig!.fechaInicio);
    var total = 0.0;
    for (final remito in _remitos) {
      if (!remito.esConfirmado) continue;
      if (_soloFecha(remito.fecha).isBefore(desde)) continue;
      if (!remito.creadoEn.isAfter(creadoEn)) continue;
      if (hasta != null && remito.creadoEn.isAfter(hasta)) continue;
      for (final item in (_remitoItems[remito.id] ?? const <RemitoItem>[])) {
        if (stockDeTipoCarne(item.tipoCarne) != tipo) continue;
        total += item.cantidadMedias * equivalenciaEnMedias(item.tipoCarne);
      }
    }
    return total;
  }

  /// El recuento más reciente de un tipo (el que manda para comparar).
  DepositoMovimiento? _ultimoRecuento(String tipo) {
    final desde = _soloFecha(_depositoConfig!.fechaInicio);
    DepositoMovimiento? ultimo;
    for (final mov in _depositoMovimientos) {
      if (mov.tipo != tipo || !mov.esRecuento) continue;
      if (_soloFecha(mov.fecha).isBefore(desde)) continue;
      if (ultimo == null || mov.creadoEn.isAfter(ultimo.creadoEn)) {
        ultimo = mov;
      }
    }
    return ultimo;
  }

  /// Movimientos del más nuevo al más viejo, opcionalmente de un solo tipo.
  List<DepositoMovimiento> movimientosDeposito({String? tipo}) {
    final lista = _depositoMovimientos
        .where((m) => tipo == null || m.tipo == tipo)
        .toList()
      ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    return lista;
  }

  // ── ABM del depósito ──

  Future<bool> guardarDepositoConfig(DepositoConfig config) async {
    try {
      _depositoConfig = await _db.guardarDepositoConfig(config);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al guardar la configuración del depósito: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> registrarMovimientoDeposito(DepositoMovimiento mov) async {
    try {
      final creado = await _db.insertDepositoMovimiento(mov);
      _depositoMovimientos.insert(0, creado);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al registrar el movimiento: $e';
      notifyListeners();
      return false;
    }
  }

  /// Borra un movimiento. Como en proveedores, primero escribe la fila de
  /// auditoría con el motivo y después borra: un movimiento que desaparece
  /// sin dejar rastro sería el mismo agujero que este módulo vino a tapar.
  Future<bool> eliminarMovimientoDeposito(
    DepositoMovimiento mov, {
    required String observacion,
  }) async {
    try {
      await _db.insertDepositoMovimientoEliminado(
        DepositoMovimientoEliminado.desde(
          mov,
          observacion: observacion,
          eliminadoPor: _usuarioActual?.nombreCompleto,
        ),
      );
      await _db.deleteDepositoMovimiento(mov.id);
      _depositoMovimientos.removeWhere((m) => m.id == mov.id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Error al eliminar el movimiento: $e';
      notifyListeners();
      return false;
    }
  }
}

/// Bucket de deuda para el cálculo FIFO de vencidos: un remito confirmado o
/// una nota de débito. `deuda` es el saldo pendiente tras aplicar créditos.
class DeudaBucket {
  final DateTime fecha;
  final int orden;
  final DateTime vencimiento;
  final Remito? remito;
  final NotaCreditoDebito? notaDebito;
  double deuda;

  DeudaBucket({
    required this.fecha,
    required this.orden,
    required this.vencimiento,
    this.remito,
    this.notaDebito,
    required this.deuda,
  });

  // ═══════════════════════════════════════════
}
