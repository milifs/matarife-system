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
  List<PagoEliminado> _pagosEliminados = [];
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
  List<PagoEliminado> get pagosEliminados => _pagosEliminados;
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
        _db.getNotasPedido(),
        _db.getCostoSemana(DateTime.now()),
        _db.getAllCostosSemana(),
      ]);
      _vendedores = results[0] as List<Vendedor>;
      _clientes = results[1] as List<Cliente>;
      _remitos = results[2] as List<Remito>;
      _pagos = results[3] as List<Pago>;
      _pagosEliminados = results[4] as List<PagoEliminado>;
      _notasPedido = results[5] as List<NotaPedido>;
      _costoSemanaActual = results[6] as CostoSemanal?;
      _costosSemanales = results[7] as List<CostoSemanal>;

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
      _saldosClientes[cliente.id] = totalRemitos - totalPagos;
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

  Future<void> eliminarRemito(String remitoId) async {
    try {
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
  // COSTO SEMANAL
  // ═══════════════════════════════════════════

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

  /// Clientes con saldo vencido
  List<Map<String, dynamic>> clientesConSaldoVencido() {
    final resultado = <Map<String, dynamic>>[];
    for (final cliente in _clientes) {
      final saldo = _saldosClientes[cliente.id] ?? 0;
      if (saldo <= 0) continue;

      final remitosCliente =
          _remitos.where((r) => r.clienteId == cliente.id && r.esConfirmado).toList();
      if (remitosCliente.isEmpty) continue;

      // Ordenar por fecha ascendente para aplicar FIFO
      remitosCliente.sort((a, b) => a.fecha.compareTo(b.fecha));

      // Calcular cuánto se ha pagado en total
      final totalPagos = _pagos
          .where((p) => p.clienteId == cliente.id)
          .fold<double>(0, (s, p) => s + p.montoTotal);

      // Aplicar pagos FIFO y encontrar el primer remito con deuda pendiente
      double pagosRestantes = totalPagos;
      Remito? primerRemitoConDeuda;
      for (final r in remitosCliente) {
        if (pagosRestantes >= r.totalPesos) {
          pagosRestantes -= r.totalPesos;
        } else {
          primerRemitoConDeuda = r;
          break;
        }
      }

      if (primerRemitoConDeuda == null) continue;

      final vencimiento = primerRemitoConDeuda.fecha
          .add(Duration(days: cliente.plazoPagoDias));
      final diasVencido = DateTime.now().difference(vencimiento).inDays;

      if (diasVencido > 0) {
        resultado.add({
          'cliente': cliente,
          'saldo': saldo,
          'diasVencido': diasVencido,
          'vendedor': vendedorPorId(cliente.vendedorId),
        });
      }
    }

    // Ordenar por días vencido (más vencido primero)
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

  /// Todos los remitos con deuda vencida (FIFO), ordenados por días vencido desc
  List<Map<String, dynamic>> todosRemitosVencidos() {
    final resultado = <Map<String, dynamic>>[];
    final ahora = DateTime.now();

    for (final cliente in _clientes) {
      final saldo = _saldosClientes[cliente.id] ?? 0;
      if (saldo <= 0) continue;

      final remitosCliente = _remitos
          .where((r) => r.clienteId == cliente.id && r.esConfirmado)
          .toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

      if (remitosCliente.isEmpty) continue;

      final totalPagos = _pagos
          .where((p) => p.clienteId == cliente.id)
          .fold<double>(0, (s, p) => s + p.montoTotal);

      double pagosRestantes = totalPagos;
      for (final r in remitosCliente) {
        if (pagosRestantes >= r.totalPesos) {
          pagosRestantes -= r.totalPesos;
        } else {
          final deuda = r.totalPesos - pagosRestantes;
          pagosRestantes = 0;
          final vencimiento =
              r.fecha.add(Duration(days: cliente.plazoPagoDias));
          final diasVencido = ahora.difference(vencimiento).inDays;
          if (diasVencido > 0) {
            resultado.add({
              'remito': r,
              'cliente': cliente,
              'vendedor': vendedorPorId(cliente.vendedorId),
              'diasVencido': diasVencido,
              'deuda': deuda,
            });
          }
        }
      }
    }

    resultado.sort((a, b) =>
        (b['diasVencido'] as int).compareTo(a['diasVencido'] as int));
    return resultado;
  }

  /// Todos los remitos con deuda NO vencida (FIFO), ordenados por días restantes desc
  List<Map<String, dynamic>> todosRemitosNoVencidos() {
    final resultado = <Map<String, dynamic>>[];
    final ahora = DateTime.now();

    for (final cliente in _clientes) {
      final saldo = _saldosClientes[cliente.id] ?? 0;
      if (saldo <= 0) continue;

      final remitosCliente = _remitos
          .where((r) => r.clienteId == cliente.id && r.esConfirmado)
          .toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));

      if (remitosCliente.isEmpty) continue;

      final totalPagos = _pagos
          .where((p) => p.clienteId == cliente.id)
          .fold<double>(0, (s, p) => s + p.montoTotal);

      double pagosRestantes = totalPagos;
      for (final r in remitosCliente) {
        if (pagosRestantes >= r.totalPesos) {
          pagosRestantes -= r.totalPesos;
        } else {
          final deuda = r.totalPesos - pagosRestantes;
          pagosRestantes = 0;
          final vencimiento =
              r.fecha.add(Duration(days: cliente.plazoPagoDias));
          final diasVencido = ahora.difference(vencimiento).inDays;
          if (diasVencido <= 0) {
            resultado.add({
              'remito': r,
              'cliente': cliente,
              'vendedor': vendedorPorId(cliente.vendedorId),
              'diasRestantes': -diasVencido,
              'deuda': deuda,
            });
          }
        }
      }
    }

    resultado.sort((a, b) =>
        (b['diasRestantes'] as int).compareTo(a['diasRestantes'] as int));
    return resultado;
  }

  /// Cantidad de remitos con deuda vencida para un cliente (FIFO)
  int remitosVencidosCliente(String clienteId) {
    final cliente = _clientes.firstWhere(
      (c) => c.id == clienteId,
      orElse: () => Cliente(
          nombreRazonSocial: '', telefono: '', vendedorId: '', plazoPagoDias: 0),
    );
    final remitosCliente = _remitos
        .where((r) => r.clienteId == clienteId && r.esConfirmado)
        .toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));

    final totalPagos = _pagos
        .where((p) => p.clienteId == clienteId)
        .fold<double>(0, (s, p) => s + p.montoTotal);

    double pagosRestantes = totalPagos;
    int vencidos = 0;
    final ahora = DateTime.now();
    for (final r in remitosCliente) {
      if (pagosRestantes >= r.totalPesos) {
        pagosRestantes -= r.totalPesos;
      } else {
        pagosRestantes = 0;
        final vencimiento =
            r.fecha.add(Duration(days: cliente.plazoPagoDias));
        if (ahora.difference(vencimiento).inDays > 0) vencidos++;
      }
    }
    return vencidos;
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

  String _normalizarTipo(String tipo) {
    final t = tipo.toLowerCase().trim();
    if (t.contains('cerdo')) return 'Cerdo';
    if (t.contains('novillo') || t.contains('ternera') || t.contains('vaquillona')) {
      return 'Novillo';
    }
    return tipo; // Pollo, otro, etc.
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

  Future<void> eliminarNotaPedido(String ndpId) async {
    try {
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
}
