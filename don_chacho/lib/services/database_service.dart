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

  /// PostgREST corta cualquier `.select()` en 1000 filas por defecto y
  /// descarta el resto SIN error. Este helper pagina en bloques de 1000
  /// hasta agotar el resultado, para que una lectura de tabla completa
  /// nunca pueda perder filas en silencio a medida que la tabla crece
  /// (bug real: v18.22 en remitos/pagos, v18.34 en notas de pedido).
  /// Usarlo en toda lectura SIN filtro acotado a un padre (cliente/remito/
  /// pago puntual); esas quedan chicas por construcción y no lo necesitan.
  Future<List<Map<String, dynamic>>> _paginado(
    PostgrestTransformBuilder<PostgrestList> Function(int from, int to)
        pagina,
  ) async {
    const pageSize = 1000;
    final data = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final batch = await pagina(from, from + pageSize - 1);
      data.addAll(batch);
      if (batch.length < pageSize) break;
      from += pageSize;
    }
    return data;
  }

  // ═══════════════════════════════════════════
  // VENDEDORES
  // ═══════════════════════════════════════════

  Future<List<Vendedor>> getVendedores() async {
    final data = await _paginado((from, to) => _client
        .from('vendedores')
        .select()
        .order('apellido')
        .range(from, to));
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
    await _client.from('vendedores').delete().eq('id', id);
  }

  // Cuenta TODOS los clientes que apuntan al vendedor, incluidos los
  // desactivados (activo=false). Se usa para bloquear el borrado del
  // vendedor: los clientes soft-deleteados siguen violando la FK.
  Future<int> contarClientesDeVendedor(String vendedorId) async {
    final data = await _client
        .from('clientes')
        .select('id')
        .eq('vendedor_id', vendedorId);
    return (data as List).length;
  }

  // ═══════════════════════════════════════════
  // CLIENTES
  // ═══════════════════════════════════════════

  Future<List<Cliente>> getClientes({String? vendedorId}) async {
    final data = await _paginado((from, to) {
      var query = _client.from('clientes').select().eq('activo', true);
      if (vendedorId != null) {
        query = query.eq('vendedor_id', vendedorId);
      }
      return query.order('nombre_razon_social').range(from, to);
    });
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
    final data = await _paginado((from, to) {
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
      return query
          .order('fecha', ascending: false)
          .order('id')
          .range(from, to);
    });
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
    final data = await _paginado((from, to) => _client
        .from('remito_items')
        .select()
        .order('id')
        .range(from, to));
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
    final data = await _paginado((from, to) {
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
      return query
          .order('fecha', ascending: false)
          .order('id')
          .range(from, to);
    });
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
    final data = await _paginado((from, to) => _client
        .from('pagos_eliminados')
        .select()
        .order('eliminado_en', ascending: false)
        .range(from, to));
    return data.map((e) => PagoEliminado.fromMap(e)).toList();
  }

  Future<void> insertRemitoEliminado(RemitoEliminado re) async {
    await _client.from('remitos_eliminados').insert(re.toMap());
  }

  Future<List<RemitoEliminado>> getRemitoEliminados() async {
    final data = await _paginado((from, to) => _client
        .from('remitos_eliminados')
        .select()
        .order('eliminado_en', ascending: false)
        .range(from, to));
    return data.map((e) => RemitoEliminado.fromMap(e)).toList();
  }

  Future<void> insertNotaPedidoEliminada(NotaPedidoEliminada ne) async {
    await _client.from('notas_pedido_eliminadas').insert(ne.toMap());
  }

  Future<List<NotaPedidoEliminada>> getNotasPedidoEliminadas() async {
    // Tolerante a que la tabla aún no exista (migración no corrida):
    // devuelve lista vacía en vez de romper la carga inicial.
    try {
      final data = await _paginado((from, to) => _client
          .from('notas_pedido_eliminadas')
          .select()
          .order('eliminado_en', ascending: false)
          .range(from, to));
      return data.map((e) => NotaPedidoEliminada.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
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
    final data = await _paginado((from, to) => _client
        .from('costos_semana')
        .select()
        .order('semana_inicio', ascending: false)
        .range(from, to));
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
    final data = await _paginado((from, to) => _client
        .from('notas_pedido')
        .select()
        .order('creado_en', ascending: false)
        .order('id')
        .range(from, to));

    if (data.isEmpty) return [];

    // Todos los items, paginados igual
    final allItemsData = await _paginado((from, to) => _client
        .from('nota_pedido_items')
        .select()
        .order('id')
        .range(from, to));
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

  // ═══════════════════════════════════════════
  // NOTAS DE CRÉDITO / DÉBITO
  // ═══════════════════════════════════════════

  Future<List<NotaCreditoDebito>> getNotasCreditoDebito() async {
    // Tolerante a que la tabla aún no exista (migración no corrida):
    // devuelve lista vacía en vez de romper la carga inicial.
    try {
      final data = await _paginado((from, to) => _client
          .from('notas_credito_debito')
          .select()
          .order('creado_en', ascending: false)
          .range(from, to));
      return data.map((e) => NotaCreditoDebito.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<NotaCreditoDebito> insertNotaCreditoDebito(
      NotaCreditoDebito nota) async {
    final data = await _client
        .from('notas_credito_debito')
        .insert(nota.toMap())
        .select()
        .single();
    return NotaCreditoDebito.fromMap(data);
  }

  Future<void> deleteNotaCreditoDebito(
    NotaCreditoDebito nota, {
    String? eliminadoPor,
  }) async {
    // Auditoría best-effort antes de borrar.
    try {
      await _client.from('notas_cd_eliminadas').insert({
        'nota_id': nota.id,
        'cliente_id': nota.clienteId,
        'tipo': nota.tipo,
        'fecha': nota.fecha.toIso8601String(),
        'numero': nota.numero,
        'monto': nota.monto,
        'motivo': nota.motivo,
        'eliminado_por': eliminadoPor,
      });
    } catch (_) {}
    await _client.from('notas_credito_debito').delete().eq('id', nota.id);
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
      // Usar el tipo de carne elegido en la nota de pedido.
      // Fallback: descripcion (NDPs v18.17 que guardaban el tipo ahí) y,
      // si todo viene vacío, la regla por peso (NDPs viejas de texto libre).
      final tipoElegido = item.tipoCarne.trim().isNotEmpty
          ? item.tipoCarne.trim()
          : item.descripcion.trim();
      final promKg = cantMedias > 0 ? kgTotal / cantMedias : 0.0;
      final tipoCarne =
          tipoElegido.isNotEmpty ? tipoElegido : (promKg > 60 ? 'Novillo' : 'Cerdo');
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

  // ═══════════════════════════════════════════
  // REPARTO (listas de logística semanal)
  // ═══════════════════════════════════════════

  /// Normaliza una fecha al lunes de esa semana (medianoche).
  DateTime _lunesDe(DateTime fecha) {
    final lunes = fecha.subtract(Duration(days: fecha.weekday - 1));
    return DateTime(lunes.year, lunes.month, lunes.day);
  }

  /// Trae la lista de reparto de una semana/día con sus items.
  /// Devuelve null si todavía no se cargó (o si la tabla no existe).
  Future<RepartoLista?> getRepartoLista(
      DateTime semanaInicio, String dia) async {
    try {
      final lunesStr = _lunesDe(semanaInicio).toIso8601String();
      final data = await _client
          .from('reparto_listas')
          .select()
          .eq('semana_inicio', lunesStr)
          .eq('dia', dia)
          .maybeSingle();
      if (data == null) return null;

      final lista = RepartoLista.fromMap(data);
      final itemsData = await _client
          .from('reparto_items')
          .select()
          .eq('lista_id', lista.id)
          .order('orden');
      lista.items =
          itemsData.map((e) => RepartoItem.fromMap(e)).toList();
      // Colapsar filas exactamente idénticas (mismo cliente, sucursal y medias):
      // nunca son intencionales y evita que se dupliquen en pantalla / al sembrar.
      final vistos = <String>{};
      lista.items = lista.items.where((it) {
        final clave =
            '${it.clienteId}|${it.sucursal}|${it.mediasCarne}|${it.mediasCerdo}';
        return vistos.add(clave);
      }).toList();
      return lista;
    } catch (_) {
      return null;
    }
  }

  /// Trae la lista de la semana/día, o —si todavía no existe— una plantilla
  /// nueva sembrada con los clientes de la semana anterior (mismo día),
  /// porque muchos clientes piden siempre lo mismo. Solo copia clientes,
  /// medias y sucursal; el TOTAL MEDIAS y las notas quedan en blanco (son
  /// propios de cada semana). [precargado] indica que lo devuelto es una
  /// plantilla sin guardar. Lo usan la pantalla de reparto y el asistente,
  /// para que ambos hagan update/insert/delete sobre la misma base.
  Future<({RepartoLista lista, bool precargado})> getRepartoListaOPlantilla(
      DateTime semanaInicio, String dia) async {
    final existente = await getRepartoLista(semanaInicio, dia);
    if (existente != null) {
      return (lista: existente, precargado: false);
    }
    final lunes = _lunesDe(semanaInicio);
    final previa =
        await getRepartoLista(lunes.subtract(const Duration(days: 7)), dia);
    final plantilla = RepartoLista(
      semanaInicio: lunes,
      dia: dia,
      items: [
        if (previa != null)
          for (final it in previa.items)
            RepartoItem(
              clienteId: it.clienteId,
              mediasCarne: it.mediasCarne,
              mediasCerdo: it.mediasCerdo,
              sucursal: it.sucursal,
              orden: it.orden,
            ),
      ],
    );
    return (
      lista: plantilla,
      precargado: previa != null && previa.items.isNotEmpty,
    );
  }

  /// Guarda (crea o actualiza) la lista de reparto y reemplaza sus items.
  Future<RepartoLista> guardarReparto(RepartoLista lista) async {
    final lunesStr = _lunesDe(lista.semanaInicio).toIso8601String();

    // Reusar el id de una lista existente para no violar UNIQUE(semana,dia).
    final existente = await _client
        .from('reparto_listas')
        .select('id')
        .eq('semana_inicio', lunesStr)
        .eq('dia', lista.dia)
        .maybeSingle();
    final id = existente != null ? existente['id'] as String : lista.id;

    final payload = lista.toMap()
      ..['id'] = id
      ..['semana_inicio'] = lunesStr;
    await _client.from('reparto_listas').upsert(payload);

    // Reemplazar items (más simple que diffear).
    await _client.from('reparto_items').delete().eq('lista_id', id);
    for (var i = 0; i < lista.items.length; i++) {
      final it = lista.items[i];
      it.listaId = id;
      it.orden = i;
      await _client.from('reparto_items').insert(it.toMap());
    }

    return lista;
  }

  // ═══════════════════════════════════════════
  // SOPORTE (v18.36)
  // ═══════════════════════════════════════════

  /// Tickets ordenados por los que hay que mirar primero: bloqueantes arriba,
  /// y dentro de cada grupo los más nuevos primero.
  /// Con `reportadoPor` trae solo los de ese usuario (para que vea en qué
  /// quedaron los suyos).
  Future<List<TicketSoporte>> getTicketsSoporte({
    String? reportadoPor,
  }) async {
    final data = await _paginado((from, to) {
      var query = _client.from('soportes').select();
      if (reportadoPor != null) {
        query = query.eq('reportado_por', reportadoPor);
      }
      return query
          .order('bloqueante', ascending: false)
          .order('creado_en', ascending: false)
          .range(from, to);
    });
    return data.map((e) => TicketSoporte.fromMap(e)).toList();
  }

  /// Inserta el ticket. El número lo asigna la secuencia de Postgres, así que
  /// el ticket devuelto es el que hay que usar (ya trae `numero`).
  Future<TicketSoporte> insertTicketSoporte(TicketSoporte ticket) async {
    final data = await _client
        .from('soportes')
        .insert(ticket.toMap())
        .select()
        .single();
    return TicketSoporte.fromMap(data);
  }

  Future<void> updateTicketSoporte(TicketSoporte ticket) async {
    await _client.from('soportes').update({
      'estado': ticket.estado,
      'respuesta': ticket.respuesta,
      'resuelto_en': ticket.resueltoEn?.toIso8601String(),
      'resuelto_por': ticket.resueltoPor,
    }).eq('id', ticket.id);
  }
}
