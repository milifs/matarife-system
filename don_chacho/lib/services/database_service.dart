// ============================================================
// SERVICIO DE BASE DE DATOS - Supabase
// ============================================================
// Abstrae todas las operaciones CRUD contra Supabase.
// En la Fase 1 usamos operaciones directas con el cliente.
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class DatabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ═══════════════════════════════════════════
  // VENDEDORES
  // ═══════════════════════════════════════════

  Future<List<Vendedor>> getVendedores() async {
    final data = await _client
        .from('vendedores')
        .select()
        .eq('activo', true)
        .order('apellido');
    return data.map((e) => Vendedor.fromMap(e)).toList();
  }

  Future<Vendedor> insertVendedor(Vendedor vendedor) async {
    final data = await _client
        .from('vendedores')
        .insert(vendedor.toMap())
        .select()
        .single();
    return Vendedor.fromMap(data);
  }

  Future<void> updateVendedor(Vendedor vendedor) async {
    await _client
        .from('vendedores')
        .update(vendedor.toMap())
        .eq('id', vendedor.id);
  }

  Future<void> deleteVendedor(String id) async {
    // Soft delete: marca como inactivo
    await _client.from('vendedores').update({'activo': false}).eq('id', id);
  }

  // ═══════════════════════════════════════════
  // CLIENTES
  // ═══════════════════════════════════════════

  Future<List<Cliente>> getClientes({String? vendedorId}) async {
    var query = _client.from('clientes').select().eq('activo', true);
    if (vendedorId != null) {
      query = query.eq('vendedor_id', vendedorId);
    }
    final data = await query.order('nombre_razon_social');
    return data.map((e) => Cliente.fromMap(e)).toList();
  }

  Future<Cliente> insertCliente(Cliente cliente) async {
    final data = await _client
        .from('clientes')
        .insert(cliente.toMap())
        .select()
        .single();
    return Cliente.fromMap(data);
  }

  Future<void> updateCliente(Cliente cliente) async {
    await _client
        .from('clientes')
        .update(cliente.toMap())
        .eq('id', cliente.id);
  }

  Future<void> deleteCliente(String id) async {
    await _client.from('clientes').update({'activo': false}).eq('id', id);
  }

  // ═══════════════════════════════════════════
  // REMITOS
  // ═══════════════════════════════════════════

  Future<List<Remito>> getRemitos({
    String? clienteId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    var query = _client.from('remitos').select();
    if (clienteId != null) {
      query = query.eq('cliente_id', clienteId);
    }
    if (desde != null) {
      query = query.gte('fecha', desde.toIso8601String());
    }
    if (hasta != null) {
      query = query.lte('fecha', hasta.toIso8601String());
    }
    final data = await query.order('fecha', ascending: false);
    return data.map((e) => Remito.fromMap(e)).toList();
  }

  Future<Remito> insertRemito(
      Remito remito, List<RemitoItem> items) async {
    // Calcula totales a partir de los items
    remito.totalKg = items.fold(0, (sum, item) => sum + item.kgTotal);
    remito.totalPesos = items.fold(0, (sum, item) => sum + item.subtotal);

    final remitoData = await _client
        .from('remitos')
        .insert(remito.toMap())
        .select()
        .single();

    // Inserta los items con el remito_id correcto
    for (final item in items) {
      item.remitoId = remitoData['id'];
      await _client.from('remito_items').insert(item.toMap());
    }

    return Remito.fromMap(remitoData);
  }

  Future<Remito> updateRemito(
      Remito remito, List<RemitoItem> items) async {
    // Recalcular totales
    remito.totalKg = items.fold(0, (sum, item) => sum + item.kgTotal);
    remito.totalPesos = items.fold(0, (sum, item) => sum + item.subtotal);

    // Actualizar remito
    final remitoData = await _client
        .from('remitos')
        .update(remito.toMap())
        .eq('id', remito.id)
        .select()
        .single();

    // Eliminar items viejos e insertar los nuevos (más simple que diffear)
    await _client.from('remito_items').delete().eq('remito_id', remito.id);
    for (final item in items) {
      item.remitoId = remito.id;
      await _client.from('remito_items').insert(item.toMap());
    }

    return Remito.fromMap(remitoData);
  }

  Future<void> deleteRemito(String remitoId) async {
    await _client.from('remito_items').delete().eq('remito_id', remitoId);
    await _client.from('remitos').delete().eq('id', remitoId);
  }

  Future<void> cambiarEstadoRemito({
    required String remitoId,
    required String estado,
    String? confirmadoPor,
    String? motivo,
  }) async {
    final updates = <String, dynamic>{
      'estado': estado,
      'confirmado_por': confirmadoPor,
      'confirmado_en': DateTime.now().toIso8601String(),
    };
    if (motivo != null) {
      updates['motivo_rechazo'] = motivo;
    }
    await _client.from('remitos').update(updates).eq('id', remitoId);
  }

  Future<List<RemitoItem>> getRemitoItems(String remitoId) async {
    final data = await _client
        .from('remito_items')
        .select()
        .eq('remito_id', remitoId);
    return data.map((e) => RemitoItem.fromMap(e)).toList();
  }

  /// Trae los items de TODOS los remitos en una sola query.
  /// Se agrupan en memoria por remito_id en el caller.
  Future<List<RemitoItem>> getAllRemitoItems() async {
    final data = await _client.from('remito_items').select();
    return data.map((e) => RemitoItem.fromMap(e)).toList();
  }

  // ═══════════════════════════════════════════
  // PAGOS
  // ═══════════════════════════════════════════

  Future<List<Pago>> getPagos({
    String? clienteId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    var query = _client.from('pagos').select();
    if (clienteId != null) {
      query = query.eq('cliente_id', clienteId);
    }
    if (desde != null) {
      query = query.gte('fecha', desde.toIso8601String());
    }
    if (hasta != null) {
      query = query.lte('fecha', hasta.toIso8601String());
    }
    final data = await query.order('fecha', ascending: false);
    return data.map((e) => Pago.fromMap(e)).toList();
  }

  Future<Pago> insertPago(Pago pago, List<PagoMedio> medios) async {
    // Calcula totales
    pago.montoTotal = medios.fold(0, (sum, m) => sum + m.monto);
    pago.netoRecibido = medios.fold(0, (sum, m) => sum + m.netoRecibido);

    final pagoData =
        await _client.from('pagos').insert(pago.toMap()).select().single();

    for (final medio in medios) {
      medio.pagoId = pagoData['id'];
      await _client.from('pago_medios').insert(medio.toMap());
    }

    return Pago.fromMap(pagoData);
  }

  Future<List<PagoMedio>> getPagoMedios(String pagoId) async {
    final data =
        await _client.from('pago_medios').select().eq('pago_id', pagoId);
    return data.map((e) => PagoMedio.fromMap(e)).toList();
  }

  Future<Pago> updatePago(Pago pago, List<PagoMedio> medios) async {
    // Recalcular totales
    pago.montoTotal = medios.fold(0, (sum, m) => sum + m.monto);
    pago.netoRecibido = medios.fold(0, (sum, m) => sum + m.netoRecibido);

    final pagoData = await _client
        .from('pagos')
        .update(pago.toMap())
        .eq('id', pago.id)
        .select()
        .single();

    // Reemplazar medios
    await _client.from('pago_medios').delete().eq('pago_id', pago.id);
    for (final m in medios) {
      m.pagoId = pago.id;
      await _client.from('pago_medios').insert(m.toMap());
    }

    return Pago.fromMap(pagoData);
  }

  Future<void> deletePago(String pagoId) async {
    await _client.from('pago_medios').delete().eq('pago_id', pagoId);
    await _client.from('pagos').delete().eq('id', pagoId);
  }

  Future<void> insertPagoEliminado(PagoEliminado pe) async {
    await _client.from('pagos_eliminados').insert(pe.toMap());
  }

  Future<List<PagoEliminado>> getPagosEliminados() async {
    final data = await _client
        .from('pagos_eliminados')
        .select()
        .order('eliminado_en', ascending: false);
    return data.map((e) => PagoEliminado.fromMap(e)).toList();
  }

  // ═══════════════════════════════════════════
  // COSTOS SEMANALES
  // ═══════════════════════════════════════════

  Future<CostoSemanal?> getCostoSemana(DateTime semana) async {
    final lunes = semana.subtract(Duration(days: semana.weekday - 1));
    final lunesStr = DateTime(lunes.year, lunes.month, lunes.day)
        .toIso8601String();
    final data = await _client
        .from('costos_semana')
        .select()
        .eq('semana_inicio', lunesStr)
        .maybeSingle();
    return data != null ? CostoSemanal.fromMap(data) : null;
  }

  Future<List<CostoSemanal>> getAllCostosSemana() async {
    final data = await _client
        .from('costos_semana')
        .select()
        .order('semana_inicio', ascending: false);
    return data.map<CostoSemanal>((e) => CostoSemanal.fromMap(e)).toList();
  }

  Future<CostoSemanal> insertCostoSemana(CostoSemanal costo) async {
    final data = await _client
        .from('costos_semana')
        .upsert(costo.toMap())
        .select()
        .single();
    return CostoSemanal.fromMap(data);
  }

  // ═══════════════════════════════════════════
  // CÁLCULOS DE SALDO
  // ═══════════════════════════════════════════

  /// Saldo de un cliente = total remitos - total pagos
  Future<double> getSaldoCliente(String clienteId) async {
    final remitos = await getRemitos(clienteId: clienteId);
    final pagos = await getPagos(clienteId: clienteId);
    final totalRemitos =
        remitos.fold<double>(0, (sum, r) => sum + r.totalPesos);
    final totalPagos =
        pagos.fold<double>(0, (sum, p) => sum + p.montoTotal);
    return totalRemitos - totalPagos;
  }

  /// Saldo de un vendedor = suma saldos de todos sus clientes
  Future<double> getSaldoVendedor(String vendedorId) async {
    final clientes = await getClientes(vendedorId: vendedorId);
    double total = 0;
    for (final c in clientes) {
      total += await getSaldoCliente(c.id);
    }
    return total;
  }

  // Storage de fotos se implementa en Fase 3

  // ═══════════════════════════════════════════
  // NOTAS DE PEDIDO
  // ═══════════════════════════════════════════

  Future<List<NotaPedido>> getNotasPedido() async {
    final data = await _client
        .from('notas_pedido')
        .select()
        .order('creado_en', ascending: false);

    if (data.isEmpty) return [];

    // Una sola query para TODOS los items
    final allItemsData = await _client.from('nota_pedido_items').select();
    final itemsPorNdp = <String, List<NotaPedidoItem>>{};
    for (final row in allItemsData) {
      final item = NotaPedidoItem.fromMap(row);
      itemsPorNdp.putIfAbsent(item.notaPedidoId, () => []).add(item);
    }

    return data
        .map<NotaPedido>((row) => NotaPedido.fromMap(
              row,
              items: itemsPorNdp[row['id']] ?? const [],
            ))
        .toList();
  }

  Future<NotaPedido> insertNotaPedido(
      NotaPedido ndp, List<NotaPedidoItem> items) async {
    ndp.totalKg = items.fold(0, (s, i) => s + i.totalKg);
    ndp.totalPesos = items.fold(0, (s, i) => s + i.totalPesos);

    final ndpData = await _client
        .from('notas_pedido')
        .insert(ndp.toMap())
        .select()
        .single();

    for (final item in items) {
      item.notaPedidoId = ndpData['id'];
      await _client.from('nota_pedido_items').insert(item.toMap());
    }

    final itemsData = await _client
        .from('nota_pedido_items')
        .select()
        .eq('nota_pedido_id', ndpData['id']);
    final savedItems =
        itemsData.map((e) => NotaPedidoItem.fromMap(e)).toList();
    return NotaPedido.fromMap(ndpData, items: savedItems);
  }

  Future<NotaPedido> updateNotaPedido(
      NotaPedido ndp, List<NotaPedidoItem> items) async {
    ndp.totalKg = items.fold(0, (s, i) => s + i.totalKg);
    ndp.totalPesos = items.fold(0, (s, i) => s + i.totalPesos);

    final ndpData = await _client
        .from('notas_pedido')
        .update(ndp.toMap())
        .eq('id', ndp.id)
        .select()
        .single();

    await _client
        .from('nota_pedido_items')
        .delete()
        .eq('nota_pedido_id', ndp.id);
    for (final item in items) {
      item.notaPedidoId = ndp.id;
      await _client.from('nota_pedido_items').insert(item.toMap());
    }

    final itemsData = await _client
        .from('nota_pedido_items')
        .select()
        .eq('nota_pedido_id', ndp.id);
    final savedItems =
        itemsData.map((e) => NotaPedidoItem.fromMap(e)).toList();
    return NotaPedido.fromMap(ndpData, items: savedItems);
  }

  Future<void> deleteNotaPedido(String ndpId) async {
    await _client
        .from('nota_pedido_items')
        .delete()
        .eq('nota_pedido_id', ndpId);
    await _client.from('notas_pedido').delete().eq('id', ndpId);
  }

  Future<void> cambiarEstadoNotaPedido({
    required String ndpId,
    required String estado,
    String? confirmadoPor,
    String? motivo,
    String? remitoId,
  }) async {
    final updates = <String, dynamic>{
      'estado': estado,
      'confirmado_por': confirmadoPor,
      'confirmado_en': DateTime.now().toIso8601String(),
    };
    if (motivo != null) updates['motivo_rechazo'] = motivo;
    if (remitoId != null) updates['remito_id'] = remitoId;
    await _client.from('notas_pedido').update(updates).eq('id', ndpId);
  }

  /// Confirma la NDP: crea Remito + RemitoItems, linkea remito_id, marca confirmada.
  /// Devuelve el Remito generado con su número asignado.
  Future<Remito> confirmarNotaPedido({
    required NotaPedido ndp,
    required String clienteId,
    required String confirmadoPorId,
    required int proximoNumeroRemito,
  }) async {
    // Construir remito
    final remito = Remito(
      clienteId: clienteId,
      fecha: ndp.fecha,
      numero: proximoNumeroRemito,
      estado: 'confirmado',
      creadoPor: confirmadoPorId,
      confirmadoPor: confirmadoPorId,
      confirmadoEn: DateTime.now(),
    );

    // Construir remito_items desde los items de la NDP
    final remitoItems = <RemitoItem>[];
    for (final item in ndp.items) {
      final kgTotal = item.totalKg;
      final cantMedias = item.cantidadMedias;
      final promKg = cantMedias > 0 ? kgTotal / cantMedias : 0.0;
      final tipoCarne = promKg > 60 ? 'Novillo' : 'Cerdo';
      final precioPorKg = item.precioPorMedia; // precioPorMedia ya es precio/kg
      remitoItems.add(RemitoItem(
        remitoId: remito.id,
        tipoCarne: tipoCarne,
        cantidadMedias: cantMedias,
        kgTotal: kgTotal,
        precioPorKg: precioPorKg,
      ));
    }

    final remitoGuardado = await insertRemito(remito, remitoItems);

    await cambiarEstadoNotaPedido(
      ndpId: ndp.id,
      estado: 'confirmado',
      confirmadoPor: confirmadoPorId,
      remitoId: remitoGuardado.id,
    );

    return remitoGuardado;
  }
}
