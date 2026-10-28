// ============================================================
// MODELOS DE DATOS - Granja Don Chacho - Matarife Terceros
// ============================================================
// Cada modelo mapea 1:1 con las tablas de Supabase (PostgreSQL)
// y contiene la lógica de serialización/deserialización.
// ============================================================

import 'package:uuid/uuid.dart';

import '../utils/formatters.dart' show compararNombres;

const _uuid = Uuid();

/// Redondeo de kilos con el criterio de la planilla: de 0,6 para arriba sube,
/// de 0,5 para abajo baja. Ojo que NO es el `.round()` de Dart, que también
/// sube el 0,5 (5403,5 -> 5404). Acá 5403,5 da 5403 y 5403,657 da 5404.
/// En negativos se aplica sobre el valor absoluto, así -28,5 da -28.
double redondearKg(double valor) {
  final signo = valor.isNegative ? -1 : 1;
  final absoluto = valor.abs();
  final entero = absoluto.floor();
  final resto = absoluto - entero;
  return (signo * (resto > 0.5 ? entero + 1 : entero)).toDouble();
}

// ─────────────────────────────────────────────
// VENDEDOR (comisionista independiente)
// ─────────────────────────────────────────────
class Vendedor {
  final String id;
  String nombre;
  String apellido;
  String telefono;
  final DateTime creadoEn;
  bool activo;

  Vendedor({
    String? id,
    required this.nombre,
    required this.apellido,
    required this.telefono,
    DateTime? creadoEn,
    this.activo = true,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  String get nombreCompleto => '$nombre $apellido';

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'apellido': apellido,
        'telefono': telefono,
        'creado_en': creadoEn.toIso8601String(),
        'activo': activo,
      };

  factory Vendedor.fromMap(Map<String, dynamic> map) => Vendedor(
        id: map['id'],
        nombre: map['nombre'] ?? '',
        apellido: map['apellido'] ?? '',
        telefono: map['telefono'] ?? '',
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        activo: map['activo'] ?? true,
      );
}

// ─────────────────────────────────────────────
// CLIENTE (pertenece a un vendedor)
// ─────────────────────────────────────────────
class Cliente {
  final String id;
  String nombreRazonSocial;
  String telefono;
  String vendedorId;
  int plazoPagoDias; // Plazo fijo en días
  String ubicacion; // Dirección manual
  String ubicacionUrl; // URL de Google Maps
  final DateTime creadoEn;
  bool activo;

  Cliente({
    String? id,
    required this.nombreRazonSocial,
    required this.telefono,
    required this.vendedorId,
    required this.plazoPagoDias,
    this.ubicacion = '',
    this.ubicacionUrl = '',
    DateTime? creadoEn,
    this.activo = true,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre_razon_social': nombreRazonSocial,
        'telefono': telefono,
        'vendedor_id': vendedorId,
        'plazo_pago_dias': plazoPagoDias,
        'ubicacion': ubicacion,
        'ubicacion_url': ubicacionUrl,
        'creado_en': creadoEn.toIso8601String(),
        'activo': activo,
      };

  factory Cliente.fromMap(Map<String, dynamic> map) => Cliente(
        id: map['id'],
        nombreRazonSocial: map['nombre_razon_social'] ?? '',
        telefono: map['telefono'] ?? '',
        vendedorId: map['vendedor_id'] ?? '',
        plazoPagoDias: map['plazo_pago_dias'] ?? 7,
        ubicacion: map['ubicacion'] ?? '',
        ubicacionUrl: map['ubicacion_url'] ?? '',
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        activo: map['activo'] ?? true,
      );
}

// ─────────────────────────────────────────────
// REMITO (cabecera)
// ─────────────────────────────────────────────
class Remito {
  final String id;
  String clienteId;
  DateTime fecha;
  int numero; // Numeración secuencial: 1, 2, 3...
  String? fotoUrl;
  double totalKg;
  double totalPesos;
  String estado; // 'pendiente', 'confirmado', 'rechazado'
  String? creadoPor; // usuario_id
  String? confirmadoPor; // usuario_id
  DateTime? confirmadoEn;
  String? motivoRechazo;
  final DateTime creadoEn;

  Remito({
    String? id,
    required this.clienteId,
    required this.fecha,
    this.numero = 0,
    this.fotoUrl,
    this.totalKg = 0,
    this.totalPesos = 0,
    this.estado = 'confirmado',
    this.creadoPor,
    this.confirmadoPor,
    this.confirmadoEn,
    this.motivoRechazo,
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool get esPendiente => estado == 'pendiente';
  bool get esConfirmado => estado == 'confirmado';
  bool get esRechazado => estado == 'rechazado';

  /// Número formateado: R-0001
  String get numeroFormateado => 'R-${numero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'cliente_id': clienteId,
        'fecha': fecha.toIso8601String(),
        'numero': numero,
        'foto_url': fotoUrl,
        'total_kg': totalKg,
        'total_pesos': totalPesos,
        'estado': estado,
        'creado_por': creadoPor,
        'confirmado_por': confirmadoPor,
        'confirmado_en': confirmadoEn?.toIso8601String(),
        'motivo_rechazo': motivoRechazo,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory Remito.fromMap(Map<String, dynamic> map) => Remito(
        id: map['id'],
        clienteId: map['cliente_id'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        numero: map['numero'] ?? 0,
        fotoUrl: map['foto_url'],
        totalKg: (map['total_kg'] ?? 0).toDouble(),
        totalPesos: (map['total_pesos'] ?? 0).toDouble(),
        estado: map['estado'] ?? 'confirmado',
        creadoPor: map['creado_por'],
        confirmadoPor: map['confirmado_por'],
        confirmadoEn: map['confirmado_en'] != null
            ? DateTime.tryParse(map['confirmado_en'])
            : null,
        motivoRechazo: map['motivo_rechazo'],
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// REMITO ITEM (línea de detalle: tipo de carne)
// ─────────────────────────────────────────────
class RemitoItem {
  final String id;
  String remitoId;
  String tipoCarne; // "Novillo", "Cerdo", etc.
  int cantidadMedias;
  double kgTotal;
  double precioPorKg;

  RemitoItem({
    String? id,
    required this.remitoId,
    required this.tipoCarne,
    required this.cantidadMedias,
    required this.kgTotal,
    required this.precioPorKg,
  }) : id = id ?? _uuid.v4();

  double get subtotal => kgTotal * precioPorKg;

  Map<String, dynamic> toMap() => {
        'id': id,
        'remito_id': remitoId,
        'tipo_carne': tipoCarne,
        'cantidad_medias': cantidadMedias,
        'kg_total': kgTotal,
        'precio_por_kg': precioPorKg,
      };

  factory RemitoItem.fromMap(Map<String, dynamic> map) => RemitoItem(
        id: map['id'],
        remitoId: map['remito_id'] ?? '',
        tipoCarne: map['tipo_carne'] ?? '',
        cantidadMedias: map['cantidad_medias'] ?? 0,
        kgTotal: (map['kg_total'] ?? 0).toDouble(),
        precioPorKg: (map['precio_por_kg'] ?? 0).toDouble(),
      );
}

// ─────────────────────────────────────────────
// PAGO (cabecera)
// ─────────────────────────────────────────────
class Pago {
  final String id;
  String clienteId;
  DateTime fecha;
  int numero; // Numeración secuencial: 1, 2, 3...
  double montoTotal;
  double netoRecibido;
  final DateTime creadoEn;
  String? registradoPor; // nombre_completo del usuario que registró el pago
  double? saldoAnterior; // saldo del cliente antes de aplicar este pago
  double? saldoNuevo; // saldo resultante después de aplicar este pago

  Pago({
    String? id,
    required this.clienteId,
    required this.fecha,
    this.numero = 0,
    required this.montoTotal,
    required this.netoRecibido,
    DateTime? creadoEn,
    this.registradoPor,
    this.saldoAnterior,
    this.saldoNuevo,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  /// Número formateado: P-0001
  String get numeroFormateado => 'P-${numero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'cliente_id': clienteId,
        'fecha': fecha.toIso8601String(),
        'numero': numero,
        'monto_total': montoTotal,
        'neto_recibido': netoRecibido,
        'creado_en': creadoEn.toIso8601String(),
        if (registradoPor != null) 'registrado_por': registradoPor,
        if (saldoAnterior != null) 'saldo_anterior': saldoAnterior,
        if (saldoNuevo != null) 'saldo_nuevo': saldoNuevo,
      };

  factory Pago.fromMap(Map<String, dynamic> map) => Pago(
        id: map['id'],
        clienteId: map['cliente_id'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        numero: map['numero'] ?? 0,
        montoTotal: (map['monto_total'] ?? 0).toDouble(),
        netoRecibido: (map['neto_recibido'] ?? 0).toDouble(),
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        registradoPor: map['registrado_por'],
        saldoAnterior: map['saldo_anterior'] != null
            ? (map['saldo_anterior'] as num).toDouble()
            : null,
        saldoNuevo: map['saldo_nuevo'] != null
            ? (map['saldo_nuevo'] as num).toDouble()
            : null,
      );
}

// ─────────────────────────────────────────────
// PAGO MEDIO (forma de pago individual)
// ─────────────────────────────────────────────
enum MedioPago { efectivo, transferencia, cheque }

class PagoMedio {
  final String id;
  String pagoId;
  MedioPago medio;
  double monto;
  double descuento; // 0 para efectivo/cheque, 6.2% para transferencia
  double netoRecibido;

  PagoMedio({
    String? id,
    required this.pagoId,
    required this.medio,
    required this.monto,
  })  : id = id ?? _uuid.v4(),
        descuento = medio == MedioPago.transferencia ? monto * 0.062 : 0,
        netoRecibido =
            medio == MedioPago.transferencia ? monto * (1 - 0.062) : monto;

  /// Recalcula descuento y neto cuando cambia el monto
  void recalcular() {
    descuento = medio == MedioPago.transferencia ? monto * 0.062 : 0;
    netoRecibido = monto - descuento;
  }

  String get medioLabel {
    switch (medio) {
      case MedioPago.efectivo:
        return 'Efectivo';
      case MedioPago.transferencia:
        return 'Transferencia';
      case MedioPago.cheque:
        return 'Cheque';
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'pago_id': pagoId,
        'medio': medio.name,
        'monto': monto,
        'descuento': descuento,
        'neto_recibido': netoRecibido,
      };

  factory PagoMedio.fromMap(Map<String, dynamic> map) {
    final medio = MedioPago.values.firstWhere(
      (m) => m.name == map['medio'],
      orElse: () => MedioPago.efectivo,
    );
    return PagoMedio(
      id: map['id'],
      pagoId: map['pago_id'] ?? '',
      medio: medio,
      monto: (map['monto'] ?? 0).toDouble(),
    )
      ..descuento = (map['descuento'] ?? 0).toDouble()
      ..netoRecibido = (map['neto_recibido'] ?? 0).toDouble();
  }
}

// ─────────────────────────────────────────────
// COSTO SEMANAL (cargado manualmente)
// ─────────────────────────────────────────────
class CostoSemanal {
  final String id;
  DateTime semanaInicio; // Lunes de la semana
  double costoPorKgNovillo;
  double costoPorKgCerdo;
  final DateTime creadoEn;

  CostoSemanal({
    String? id,
    required this.semanaInicio,
    required this.costoPorKgNovillo,
    required this.costoPorKgCerdo,
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  /// Retorna el costo según tipo de carne
  double costoPorTipo(String tipoCarne) {
    final tipo = tipoCarne.toLowerCase();
    if (tipo.contains('cerdo')) return costoPorKgCerdo;
    return costoPorKgNovillo; // Novillo es el default
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'semana_inicio': semanaInicio.toIso8601String(),
        'costo_por_kg_novillo': costoPorKgNovillo,
        'costo_por_kg_cerdo': costoPorKgCerdo,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory CostoSemanal.fromMap(Map<String, dynamic> map) => CostoSemanal(
        id: map['id'],
        semanaInicio:
            DateTime.tryParse(map['semana_inicio'] ?? '') ?? DateTime.now(),
        costoPorKgNovillo:
            (map['costo_por_kg_novillo'] ?? map['costo_por_kg'] ?? 0)
                .toDouble(),
        costoPorKgCerdo: (map['costo_por_kg_cerdo'] ?? 0).toDouble(),
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// NOTA DE PEDIDO ITEM (fila de detalle)
// ─────────────────────────────────────────────
class NotaPedidoItem {
  final String id;
  String notaPedidoId;
  String tipoCarne; // dropdown: "Novillo", "Cerdo", etc.
  String descripcion; // texto libre opcional
  int cantidadMedias;
  List<double> kgsPorMedia; // un valor por cada media
  double precioPorMedia;

  NotaPedidoItem({
    String? id,
    required this.notaPedidoId,
    this.tipoCarne = '',
    this.descripcion = '',
    required this.cantidadMedias,
    required this.kgsPorMedia,
    required this.precioPorMedia,
  }) : id = id ?? _uuid.v4();

  double get totalKg => kgsPorMedia.fold(0, (s, kg) => s + kg);
  double get totalPesos => totalKg * precioPorMedia; // precio es por kg

  Map<String, dynamic> toMap() => {
        'id': id,
        'nota_pedido_id': notaPedidoId,
        'tipo_carne': tipoCarne,
        'descripcion': descripcion,
        'cantidad_medias': cantidadMedias,
        'kgs_por_media': kgsPorMedia,
        'precio_por_media': precioPorMedia,
        'total_kg': totalKg,
        'total_pesos': totalPesos,
      };

  factory NotaPedidoItem.fromMap(Map<String, dynamic> map) {
    final kgsRaw = map['kgs_por_media'];
    final kgs = kgsRaw is List
        ? kgsRaw.map<double>((e) => (e as num).toDouble()).toList()
        : <double>[];
    return NotaPedidoItem(
      id: map['id'],
      notaPedidoId: map['nota_pedido_id'] ?? '',
      tipoCarne: map['tipo_carne'] ?? '',
      descripcion: map['descripcion'] ?? '',
      cantidadMedias: map['cantidad_medias'] ?? 1,
      kgsPorMedia: kgs,
      precioPorMedia: (map['precio_por_media'] ?? 0).toDouble(),
    );
  }
}

// ─────────────────────────────────────────────
// NOTA DE PEDIDO (cabecera)
// ─────────────────────────────────────────────
class NotaPedido {
  final String id;
  int numero;
  DateTime fecha;
  String? clienteId;
  String? clienteNombreLibre;
  String estado; // 'pendiente', 'confirmado', 'rechazado'
  String? motivoRechazo;
  String? creadoPor;
  String? confirmadoPor;
  DateTime? confirmadoEn;
  String? remitoId; // se llena al confirmar
  double totalKg;
  double totalPesos;
  final DateTime creadoEn;
  List<NotaPedidoItem> items;

  NotaPedido({
    String? id,
    this.numero = 0,
    required this.fecha,
    this.clienteId,
    this.clienteNombreLibre,
    this.estado = 'pendiente',
    this.motivoRechazo,
    this.creadoPor,
    this.confirmadoPor,
    this.confirmadoEn,
    this.remitoId,
    this.totalKg = 0,
    this.totalPesos = 0,
    DateTime? creadoEn,
    this.items = const [],
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool get esPendiente => estado == 'pendiente';
  bool get esConfirmado => estado == 'confirmado';
  bool get esRechazado => estado == 'rechazado';

  String get numeroFormateado => 'NP-${numero.toString().padLeft(4, '0')}';

  // Nombre a mostrar (lista o texto libre)
  String get clienteLabel => clienteNombreLibre?.isNotEmpty == true
      ? clienteNombreLibre!
      : '(sin cliente)';

  Map<String, dynamic> toMap() => {
        'id': id,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'cliente_id': clienteId,
        'cliente_nombre_libre': clienteNombreLibre,
        'estado': estado,
        'motivo_rechazo': motivoRechazo,
        'creado_por': creadoPor,
        'confirmado_por': confirmadoPor,
        'confirmado_en': confirmadoEn?.toIso8601String(),
        'remito_id': remitoId,
        'total_kg': totalKg,
        'total_pesos': totalPesos,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory NotaPedido.fromMap(Map<String, dynamic> map,
          {List<NotaPedidoItem> items = const []}) =>
      NotaPedido(
        id: map['id'],
        numero: map['numero'] ?? 0,
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        clienteId: map['cliente_id'],
        clienteNombreLibre: map['cliente_nombre_libre'],
        estado: map['estado'] ?? 'pendiente',
        motivoRechazo: map['motivo_rechazo'],
        creadoPor: map['creado_por'],
        confirmadoPor: map['confirmado_por'],
        confirmadoEn: map['confirmado_en'] != null
            ? DateTime.tryParse(map['confirmado_en'])
            : null,
        remitoId: map['remito_id'],
        totalKg: (map['total_kg'] ?? 0).toDouble(),
        totalPesos: (map['total_pesos'] ?? 0).toDouble(),
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        items: items,
      );
}

// ─────────────────────────────────────────────
// PAGO ELIMINADO (historial de bajas)
// ─────────────────────────────────────────────
class PagoEliminado {
  final String id;
  final String pagoId;
  final String clienteId;
  final DateTime fecha;
  final int numero;
  final double montoTotal;
  final List<Map<String, dynamic>> medios;
  final String? observacion;
  final DateTime eliminadoEn;
  final String? eliminadoPor;

  PagoEliminado({
    String? id,
    required this.pagoId,
    required this.clienteId,
    required this.fecha,
    required this.numero,
    required this.montoTotal,
    required this.medios,
    this.observacion,
    DateTime? eliminadoEn,
    this.eliminadoPor,
  })  : id = id ?? _uuid.v4(),
        eliminadoEn = eliminadoEn ?? DateTime.now();

  String get numeroFormateado => 'P-${numero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'pago_id': pagoId,
        'cliente_id': clienteId,
        'fecha': fecha.toIso8601String(),
        'numero': numero,
        'monto_total': montoTotal,
        'medios': medios,
        'observacion': observacion,
        'eliminado_por': eliminadoPor,
      };

  factory PagoEliminado.fromMap(Map<String, dynamic> map) {
    final mediosRaw = map['medios'];
    final medios = mediosRaw is List
        ? mediosRaw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];
    return PagoEliminado(
      id: map['id'],
      pagoId: map['pago_id'] ?? '',
      clienteId: map['cliente_id'] ?? '',
      fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
      numero: map['numero'] ?? 0,
      montoTotal: (map['monto_total'] ?? 0).toDouble(),
      medios: medios,
      observacion: map['observacion'],
      eliminadoEn:
          DateTime.tryParse(map['eliminado_en'] ?? '') ?? DateTime.now(),
      eliminadoPor: map['eliminado_por'],
    );
  }
}

// ─────────────────────────────────────────────
// REMITO ELIMINADO (audit log)
// ─────────────────────────────────────────────
class RemitoEliminado {
  final String id;
  final String remitoId;
  final String clienteId;
  final DateTime fecha;
  final int numero;
  final double totalKg;
  final double totalPesos;
  final String? observacion;
  final DateTime eliminadoEn;
  final String? eliminadoPor;

  RemitoEliminado({
    String? id,
    required this.remitoId,
    required this.clienteId,
    required this.fecha,
    required this.numero,
    required this.totalKg,
    required this.totalPesos,
    this.observacion,
    DateTime? eliminadoEn,
    this.eliminadoPor,
  })  : id = id ?? _uuid.v4(),
        eliminadoEn = eliminadoEn ?? DateTime.now();

  String get numeroFormateado => 'R-${numero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'remito_id': remitoId,
        'cliente_id': clienteId,
        'fecha': fecha.toIso8601String(),
        'numero': numero,
        'total_kg': totalKg,
        'total_pesos': totalPesos,
        'observacion': observacion,
        'eliminado_por': eliminadoPor,
      };

  factory RemitoEliminado.fromMap(Map<String, dynamic> map) => RemitoEliminado(
        id: map['id'],
        remitoId: map['remito_id'] ?? '',
        clienteId: map['cliente_id'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        numero: map['numero'] ?? 0,
        totalKg: (map['total_kg'] ?? 0).toDouble(),
        totalPesos: (map['total_pesos'] ?? 0).toDouble(),
        observacion: map['observacion'],
        eliminadoEn:
            DateTime.tryParse(map['eliminado_en'] ?? '') ?? DateTime.now(),
        eliminadoPor: map['eliminado_por'],
      );
}

// ─────────────────────────────────────────────
// NOTA DE PEDIDO ELIMINADA (audit log)
// ─────────────────────────────────────────────
class NotaPedidoEliminada {
  final String id;
  final String notaPedidoId;
  final int numero;
  final DateTime fecha;
  final String? clienteId;
  final String? clienteNombre;
  final String? estado;
  final double totalKg;
  final double totalPesos;
  final String? observacion;
  final DateTime eliminadoEn;
  final String? eliminadoPor;

  NotaPedidoEliminada({
    String? id,
    required this.notaPedidoId,
    required this.numero,
    required this.fecha,
    this.clienteId,
    this.clienteNombre,
    this.estado,
    required this.totalKg,
    required this.totalPesos,
    this.observacion,
    DateTime? eliminadoEn,
    this.eliminadoPor,
  })  : id = id ?? _uuid.v4(),
        eliminadoEn = eliminadoEn ?? DateTime.now();

  String get numeroFormateado => 'NP-${numero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'nota_pedido_id': notaPedidoId,
        'numero': numero,
        'fecha': fecha.toIso8601String(),
        'cliente_id': clienteId,
        'cliente_nombre': clienteNombre,
        'estado': estado,
        'total_kg': totalKg,
        'total_pesos': totalPesos,
        'observacion': observacion,
        'eliminado_por': eliminadoPor,
      };

  factory NotaPedidoEliminada.fromMap(Map<String, dynamic> map) =>
      NotaPedidoEliminada(
        id: map['id'],
        notaPedidoId: map['nota_pedido_id'] ?? '',
        numero: map['numero'] ?? 0,
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        clienteId: map['cliente_id'],
        clienteNombre: map['cliente_nombre'],
        estado: map['estado'],
        totalKg: (map['total_kg'] ?? 0).toDouble(),
        totalPesos: (map['total_pesos'] ?? 0).toDouble(),
        observacion: map['observacion'],
        eliminadoEn:
            DateTime.tryParse(map['eliminado_en'] ?? '') ?? DateTime.now(),
        eliminadoPor: map['eliminado_por'],
      );
}

// ─────────────────────────────────────────────
// NOTA DE CRÉDITO / DÉBITO (ajuste manual de saldo)
// ─────────────────────────────────────────────
// tipo 'credito' → resta al saldo del cliente (a su favor, como un pago)
// tipo 'debito'  → suma al saldo del cliente (cargo extra, como un remito)
class NotaCreditoDebito {
  final String id;
  String clienteId;
  String tipo; // 'credito' | 'debito'
  DateTime fecha;
  int numero; // secuencia separada por tipo
  double monto;
  String motivo;
  String? registradoPor; // nombre_completo del usuario
  final DateTime creadoEn;

  NotaCreditoDebito({
    String? id,
    required this.clienteId,
    required this.tipo,
    required this.fecha,
    this.numero = 0,
    required this.monto,
    this.motivo = '',
    this.registradoPor,
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool get esCredito => tipo == 'credito';
  bool get esDebito => tipo == 'debito';

  /// Número formateado: NC-0001 / ND-0001
  String get numeroFormateado =>
      '${esCredito ? 'NC' : 'ND'}-${numero.toString().padLeft(4, '0')}';

  String get tipoLabel => esCredito ? 'Nota de crédito' : 'Nota de débito';

  Map<String, dynamic> toMap() => {
        'id': id,
        'cliente_id': clienteId,
        'tipo': tipo,
        'fecha': fecha.toIso8601String(),
        'numero': numero,
        'monto': monto,
        'motivo': motivo,
        if (registradoPor != null) 'registrado_por': registradoPor,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory NotaCreditoDebito.fromMap(Map<String, dynamic> map) =>
      NotaCreditoDebito(
        id: map['id'],
        clienteId: map['cliente_id'] ?? '',
        tipo: map['tipo'] ?? 'credito',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        numero: map['numero'] ?? 0,
        monto: (map['monto'] ?? 0).toDouble(),
        motivo: map['motivo'] ?? '',
        registradoPor: map['registrado_por'],
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// REPARTO — LISTA (logística semanal, sin plata)
// ─────────────────────────────────────────────
// Dos listas por semana: 'jueves' y 'viernes'. TOTAL MEDIAS es manual;
// el sobrante se calcula en la app (total - repartido).
class RepartoLista {
  final String id;
  DateTime semanaInicio; // lunes de la semana
  String dia; // 'jueves' | 'viernes'
  int totalMediasCarne;
  int totalMediasCerdo;
  String notas;
  final DateTime creadoEn;
  List<RepartoItem> items;

  RepartoLista({
    String? id,
    required this.semanaInicio,
    required this.dia,
    this.totalMediasCarne = 0,
    this.totalMediasCerdo = 0,
    this.notas = '',
    DateTime? creadoEn,
    this.items = const [],
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  String get diaLabel =>
      dia.isEmpty ? '' : '${dia[0].toUpperCase()}${dia.substring(1)}';

  /// Suma de medias de carne ya asignadas a clientes
  int get repartidoCarne => items.fold(0, (s, i) => s + i.mediasCarne);
  int get repartidoCerdo => items.fold(0, (s, i) => s + i.mediasCerdo);

  /// Sobrante en depósito = total cargado - repartido
  int get sobranteCarne => totalMediasCarne - repartidoCarne;
  int get sobranteCerdo => totalMediasCerdo - repartidoCerdo;

  Map<String, dynamic> toMap() => {
        'id': id,
        'semana_inicio': semanaInicio.toIso8601String(),
        'dia': dia,
        'total_medias_carne': totalMediasCarne,
        'total_medias_cerdo': totalMediasCerdo,
        'notas': notas,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory RepartoLista.fromMap(Map<String, dynamic> map,
          {List<RepartoItem> items = const []}) =>
      RepartoLista(
        id: map['id'],
        semanaInicio:
            DateTime.tryParse(map['semana_inicio'] ?? '') ?? DateTime.now(),
        dia: map['dia'] ?? 'jueves',
        totalMediasCarne: map['total_medias_carne'] ?? 0,
        totalMediasCerdo: map['total_medias_cerdo'] ?? 0,
        notas: map['notas'] ?? '',
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        items: items,
      );
}

// ─────────────────────────────────────────────
// REPARTO — ITEM (fila por cliente)
// ─────────────────────────────────────────────
class RepartoItem {
  final String id;
  String listaId;
  String clienteId;
  int mediasCarne;
  int mediasCerdo;
  String sucursal; // texto libre (máx 40): a qué sucursal del cliente va
  int orden;

  RepartoItem({
    String? id,
    this.listaId = '',
    required this.clienteId,
    this.mediasCarne = 0,
    this.mediasCerdo = 0,
    this.sucursal = '',
    this.orden = 0,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'lista_id': listaId,
        'cliente_id': clienteId,
        'medias_carne': mediasCarne,
        'medias_cerdo': mediasCerdo,
        'sucursal': sucursal,
        'orden': orden,
      };

  factory RepartoItem.fromMap(Map<String, dynamic> map) => RepartoItem(
        id: map['id'],
        listaId: map['lista_id'] ?? '',
        clienteId: map['cliente_id'] ?? '',
        mediasCarne: map['medias_carne'] ?? 0,
        mediasCerdo: map['medias_cerdo'] ?? 0,
        sucursal: map['sucursal'] ?? '',
        orden: map['orden'] ?? 0,
      );
}

// ─────────────────────────────────────────────
// PERMISO (catálogo fijo)
// ─────────────────────────────────────────────
class Permiso {
  final String id;
  final String nombre;
  final String descripcion;

  Permiso({
    required this.id,
    required this.nombre,
    this.descripcion = '',
  });

  factory Permiso.fromMap(Map<String, dynamic> map) => Permiso(
        id: map['id'] ?? '',
        nombre: map['nombre'] ?? '',
        descripcion: map['descripcion'] ?? '',
      );
}

// ─────────────────────────────────────────────
// ROL
// ─────────────────────────────────────────────
class Rol {
  final String id;
  String nombre;
  bool esAdmin;
  List<String> permisoIds; // IDs de permisos asignados
  final DateTime creadoEn;

  Rol({
    String? id,
    required this.nombre,
    this.esAdmin = false,
    this.permisoIds = const [],
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool tienePermiso(String permisoId) =>
      esAdmin || permisoIds.contains(permisoId);

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'es_admin': esAdmin,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory Rol.fromMap(Map<String, dynamic> map,
          {List<String> permisoIds = const []}) =>
      Rol(
        id: map['id'],
        nombre: map['nombre'] ?? '',
        esAdmin: map['es_admin'] ?? false,
        permisoIds: permisoIds,
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// USUARIO
// ─────────────────────────────────────────────
class Usuario {
  final String id;
  String usuario;
  String passwordHash;
  String rolId;
  String nombreCompleto;
  bool activo;
  final DateTime creadoEn;

  // Se carga aparte
  Rol? rol;

  Usuario({
    String? id,
    required this.usuario,
    required this.passwordHash,
    required this.rolId,
    required this.nombreCompleto,
    this.activo = true,
    DateTime? creadoEn,
    this.rol,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool tienePermiso(String permisoId) => rol?.tienePermiso(permisoId) ?? false;
  bool get esAdmin => rol?.esAdmin ?? false;

  Map<String, dynamic> toMap() => {
        'id': id,
        'usuario': usuario,
        'password_hash': passwordHash,
        'rol_id': rolId,
        'nombre_completo': nombreCompleto,
        'activo': activo,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory Usuario.fromMap(Map<String, dynamic> map) => Usuario(
        id: map['id'],
        usuario: map['usuario'] ?? '',
        passwordHash: map['password_hash'] ?? '',
        rolId: map['rol_id'] ?? '',
        nombreCompleto: map['nombre_completo'] ?? '',
        activo: map['activo'] ?? true,
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// TICKET DE SOPORTE (v18.36)
// ─────────────────────────────────────────────
// Reclamo que carga el cliente cuando algo no funciona. El número lo asigna
// Postgres (IDENTITY), así que no se manda en el insert.
class TicketSoporte {
  final String id;
  int numero;
  String modulo;
  String descripcion;
  bool bloqueante;
  String? adjuntoPath; // path dentro del bucket, no URL
  String estado; // 'abierto' | 'en_revision' | 'resuelto'
  String respuesta;
  String? reportadoPor;
  String? rol;
  String? appVersion;
  String? plataforma;
  final DateTime creadoEn;
  DateTime? resueltoEn;
  String? resueltoPor;

  TicketSoporte({
    String? id,
    this.numero = 0,
    this.modulo = '',
    this.descripcion = '',
    this.bloqueante = false,
    this.adjuntoPath,
    this.estado = 'abierto',
    this.respuesta = '',
    this.reportadoPor,
    this.rol,
    this.appVersion,
    this.plataforma,
    DateTime? creadoEn,
    this.resueltoEn,
    this.resueltoPor,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool get esAbierto => estado == 'abierto';
  bool get esEnRevision => estado == 'en_revision';
  bool get esResuelto => estado == 'resuelto';
  bool get tieneAdjunto => (adjuntoPath ?? '').isNotEmpty;

  /// Número formateado: S-0001
  String get numeroFormateado => 'S-${numero.toString().padLeft(4, '0')}';

  String get estadoLabel => switch (estado) {
        'en_revision' => 'En revisión',
        'resuelto' => 'Resuelto',
        _ => 'Abierto',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        // numero lo asigna la secuencia de Postgres en el insert
        if (numero > 0) 'numero': numero,
        'modulo': modulo,
        'descripcion': descripcion,
        'bloqueante': bloqueante,
        if (adjuntoPath != null) 'adjunto_path': adjuntoPath,
        'estado': estado,
        'respuesta': respuesta,
        if (reportadoPor != null) 'reportado_por': reportadoPor,
        if (rol != null) 'rol': rol,
        if (appVersion != null) 'app_version': appVersion,
        if (plataforma != null) 'plataforma': plataforma,
        'creado_en': creadoEn.toIso8601String(),
        if (resueltoEn != null) 'resuelto_en': resueltoEn!.toIso8601String(),
        if (resueltoPor != null) 'resuelto_por': resueltoPor,
      };

  factory TicketSoporte.fromMap(Map<String, dynamic> map) => TicketSoporte(
        id: map['id'],
        numero: map['numero'] ?? 0,
        modulo: map['modulo'] ?? '',
        descripcion: map['descripcion'] ?? '',
        bloqueante: map['bloqueante'] ?? false,
        adjuntoPath: map['adjunto_path'],
        estado: map['estado'] ?? 'abierto',
        respuesta: map['respuesta'] ?? '',
        reportadoPor: map['reportado_por'],
        rol: map['rol'],
        appVersion: map['app_version'],
        plataforma: map['plataforma'],
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        resueltoEn: DateTime.tryParse(map['resuelto_en'] ?? ''),
        resueltoPor: map['resuelto_por'],
      );
}

// ─────────────────────────────────────────────
// PROVEEDOR (le vende el animal vivo a Joaco)
// ─────────────────────────────────────────────
// Nada que ver con los clientes: acá es plata que SALE.
// Los tres números son el default del proveedor y se copian a la carga,
// donde quedan editables (el precio del kg vivo cambia seguido).
class Proveedor {
  /// Los dos tipos de animal que se compran. En minúscula, igual que
  /// `CargaPago.medio`; para mostrar en pantalla está [tipoLabel].
  static const tipoNovillo = 'novillo';
  static const tipoCerdo = 'cerdo';

  final String id;
  String nombre;

  /// Qué vende: [tipoNovillo] o [tipoCerdo].
  ///
  /// Vive en el proveedor y NO se congela en cada carga (a diferencia de
  /// desvaste/precio/rinde) porque la especie no cambia semana a semana: si
  /// se cargó mal, corregir el proveedor tiene que arreglar las cargas viejas
  /// también. Un proveedor que venda las dos cosas se carga dos veces.
  String tipo;

  double desvastePorcentaje; // 5 => se paga el 95% del peso vivo
  double precioKgVivo;
  double rindeAsegurado; // 58 => el proveedor asegura 58% de rinde
  bool activo;
  final DateTime creadoEn;

  Proveedor({
    String? id,
    required this.nombre,
    this.tipo = tipoNovillo,
    this.desvastePorcentaje = 5,
    this.precioKgVivo = 0,
    this.rindeAsegurado = 58,
    this.activo = true,
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  bool get esCerdo => tipo == tipoCerdo;

  /// 'Novillo' / 'Cerdo' — el mismo vocabulario que usa `CostoSemanal`
  /// para separar costo por kg de novillo y de cerdo.
  String get tipoLabel => esCerdo ? 'Cerdo' : 'Novillo';

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'tipo': tipo,
        'desvaste_porcentaje': desvastePorcentaje,
        'precio_kg_vivo': precioKgVivo,
        'rinde_asegurado': rindeAsegurado,
        'activo': activo,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory Proveedor.fromMap(Map<String, dynamic> map) => Proveedor(
        id: map['id'],
        nombre: map['nombre'] ?? '',
        // Si la migración todavía no corrió, la columna no viene: novillo.
        // Cualquier otro valor también cae en novillo en vez de romper la
        // pantalla; el CHECK de la BD ya limita los dos válidos.
        tipo: '${map['tipo']}'.toLowerCase().contains('cerdo')
            ? tipoCerdo
            : tipoNovillo,
        desvastePorcentaje: (map['desvaste_porcentaje'] ?? 5).toDouble(),
        precioKgVivo: (map['precio_kg_vivo'] ?? 0).toDouble(),
        rindeAsegurado: (map['rinde_asegurado'] ?? 58).toDouble(),
        activo: map['activo'] ?? true,
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// CARGA (una compra de animales a un proveedor)
// ─────────────────────────────────────────────
// Equivale a una hoja del Excel "Proveedores-Pagos".
// kg_neto, total_a_pagar y rinde_carga son columnas GENERADAS en Postgres:
// se leen pero NUNCA se mandan en el insert/update (Postgres las rechaza).
// Los getters de abajo replican la cuenta para poder mostrarla en vivo
// mientras se tipea el formulario, antes de que el servidor responda.
class Carga {
  final String id;
  int numero; // lo asigna la secuencia de Postgres => PP-0001
  String proveedorId;
  DateTime fecha;
  int cantidadAnimales;
  double kgVivo;
  double desvastePorcentaje;
  double precioKgVivo;
  double rindeAsegurado;
  double? kgMediaRes; // null hasta que se faena
  String observacion;
  String? registradoPor;
  final DateTime creadoEn;

  // Valores calculados que vienen del servidor (pueden ser null si la fila
  // todavía no volvió de Postgres)
  final double? kgNetoServidor;
  final double? totalAPagarServidor;
  final double? rindeCargaServidor;

  Carga({
    String? id,
    this.numero = 0,
    required this.proveedorId,
    required this.fecha,
    this.cantidadAnimales = 0,
    this.kgVivo = 0,
    this.desvastePorcentaje = 5,
    this.precioKgVivo = 0,
    this.rindeAsegurado = 58,
    this.kgMediaRes,
    this.observacion = '',
    this.registradoPor,
    DateTime? creadoEn,
    this.kgNetoServidor,
    this.totalAPagarServidor,
    this.rindeCargaServidor,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  String get numeroFormateado => 'PP-${numero.toString().padLeft(4, '0')}';

  /// Kg que se pagan: peso vivo menos el desvaste
  double get kgNeto => kgVivo * (100 - desvastePorcentaje) / 100;

  /// Lo que hay que pagarle al proveedor por esta carga
  double get totalAPagar => kgNeto * precioKgVivo;

  /// Rinde real de la carga (%). Null mientras no se cargue el kg media res.
  double? get rindeCarga {
    if (kgMediaRes == null || kgNeto == 0) return null;
    return kgMediaRes! * 100 / kgNeto;
  }

  /// true cuando ya se faenó y se cargó el resultado
  bool get tieneFaena => kgMediaRes != null;

  /// Kg que deberían haber salido según el rinde asegurado.
  /// Va redondeado a kilos enteros (ver [redondearKg]): los gramos no se
  /// discuten con el proveedor y así los tres números del bloque de rinde
  /// cierran a la vista (esperados - obtenidos = diferencia).
  double get kgEsperados => redondearKg(kgEsperadosExacto);

  /// El valor sin redondear, por si algún cálculo necesita el detalle fino.
  double get kgEsperadosExacto => kgNeto * rindeAsegurado / 100;

  /// Diferencia de rinde en kg (positivo = rindió MENOS de lo asegurado).
  /// Null mientras no se haya faenado.
  double? get diferenciaRindeKg {
    if (kgMediaRes == null) return null;
    return redondearKg(kgEsperados - kgMediaRes!);
  }

  /// Diferencia de rinde valorizada al precio del kg vivo
  double? get diferenciaRindePesos {
    final kg = diferenciaRindeKg;
    if (kg == null) return null;
    return kg * precioKgVivo;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        // numero lo pone la secuencia: si va en 0 no se manda
        if (numero > 0) 'numero': numero,
        'proveedor_id': proveedorId,
        'fecha': fecha.toIso8601String(),
        'cantidad_animales': cantidadAnimales,
        'kg_vivo': kgVivo,
        'desvaste_porcentaje': desvastePorcentaje,
        'precio_kg_vivo': precioKgVivo,
        'rinde_asegurado': rindeAsegurado,
        'kg_media_res': kgMediaRes,
        'observacion': observacion,
        if (registradoPor != null) 'registrado_por': registradoPor,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory Carga.fromMap(Map<String, dynamic> map) => Carga(
        id: map['id'],
        numero: map['numero'] ?? 0,
        proveedorId: map['proveedor_id'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        cantidadAnimales: map['cantidad_animales'] ?? 0,
        kgVivo: (map['kg_vivo'] ?? 0).toDouble(),
        desvastePorcentaje: (map['desvaste_porcentaje'] ?? 5).toDouble(),
        precioKgVivo: (map['precio_kg_vivo'] ?? 0).toDouble(),
        rindeAsegurado: (map['rinde_asegurado'] ?? 58).toDouble(),
        kgMediaRes: map['kg_media_res'] == null
            ? null
            : (map['kg_media_res']).toDouble(),
        observacion: map['observacion'] ?? '',
        registradoPor: map['registrado_por'],
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
        kgNetoServidor:
            map['kg_neto'] == null ? null : (map['kg_neto']).toDouble(),
        totalAPagarServidor: map['total_a_pagar'] == null
            ? null
            : (map['total_a_pagar']).toDouble(),
        rindeCargaServidor:
            map['rinde_carga'] == null ? null : (map['rinde_carga']).toDouble(),
      );

  Carga copyWith({
    DateTime? fecha,
    String? proveedorId,
    int? cantidadAnimales,
    double? kgVivo,
    double? desvastePorcentaje,
    double? precioKgVivo,
    double? rindeAsegurado,
    double? kgMediaRes,
    bool limpiarKgMediaRes = false,
    String? observacion,
  }) =>
      Carga(
        id: id,
        numero: numero,
        proveedorId: proveedorId ?? this.proveedorId,
        fecha: fecha ?? this.fecha,
        cantidadAnimales: cantidadAnimales ?? this.cantidadAnimales,
        kgVivo: kgVivo ?? this.kgVivo,
        desvastePorcentaje: desvastePorcentaje ?? this.desvastePorcentaje,
        precioKgVivo: precioKgVivo ?? this.precioKgVivo,
        rindeAsegurado: rindeAsegurado ?? this.rindeAsegurado,
        kgMediaRes: limpiarKgMediaRes ? null : (kgMediaRes ?? this.kgMediaRes),
        observacion: observacion ?? this.observacion,
        registradoPor: registradoPor,
        creadoEn: creadoEn,
      );
}

// ─────────────────────────────────────────────
// PAGO DE CARGA (plata que sale hacia el proveedor)
// ─────────────────────────────────────────────
// A diferencia de los pagos de clientes, acá la transferencia NO tiene
// descuento del 6,2%: ese descuento es sobre lo que se COBRA, no sobre
// lo que se paga. Por eso no hay neto_recibido.
class CargaPago {
  final String id;
  String cargaId;
  DateTime fecha;
  String medio; // 'efectivo' | 'transferencia' | 'cheque'
  double monto;
  String? registradoPor;
  final DateTime creadoEn;

  CargaPago({
    String? id,
    required this.cargaId,
    required this.fecha,
    required this.medio,
    required this.monto,
    this.registradoPor,
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        creadoEn = creadoEn ?? DateTime.now();

  String get medioLabel {
    switch (medio) {
      case 'transferencia':
        return 'Transferencia';
      case 'cheque':
        return 'Cheque';
      default:
        return 'Efectivo';
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'carga_id': cargaId,
        'fecha': fecha.toIso8601String(),
        'medio': medio,
        'monto': monto,
        if (registradoPor != null) 'registrado_por': registradoPor,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory CargaPago.fromMap(Map<String, dynamic> map) => CargaPago(
        id: map['id'],
        cargaId: map['carga_id'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        medio: map['medio'] ?? 'efectivo',
        monto: (map['monto'] ?? 0).toDouble(),
        registradoPor: map['registrado_por'],
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
      );
}

// ─────────────────────────────────────────────
// CARGA ELIMINADA (audit log)
// ─────────────────────────────────────────────
class CargaEliminada {
  final String id;
  final String cargaId;
  final int numero;
  final String proveedorId;
  final String proveedorNombre;
  final DateTime fecha;
  final int cantidadAnimales;
  final double kgVivo;
  final double? kgMediaRes;
  final double totalAPagar;
  final double totalPagado;
  final List<Map<String, dynamic>> pagos;
  final String observacion;
  final DateTime eliminadoEn;
  final String? eliminadoPor;

  CargaEliminada({
    String? id,
    required this.cargaId,
    required this.numero,
    required this.proveedorId,
    required this.proveedorNombre,
    required this.fecha,
    required this.cantidadAnimales,
    required this.kgVivo,
    this.kgMediaRes,
    required this.totalAPagar,
    required this.totalPagado,
    required this.pagos,
    required this.observacion,
    DateTime? eliminadoEn,
    this.eliminadoPor,
  })  : id = id ?? _uuid.v4(),
        eliminadoEn = eliminadoEn ?? DateTime.now();

  String get numeroFormateado => 'PP-${numero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'carga_id': cargaId,
        'numero': numero,
        'proveedor_id': proveedorId,
        'proveedor_nombre': proveedorNombre,
        'fecha': fecha.toIso8601String(),
        'cantidad_animales': cantidadAnimales,
        'kg_vivo': kgVivo,
        'kg_media_res': kgMediaRes,
        'total_a_pagar': totalAPagar,
        'total_pagado': totalPagado,
        'pagos': pagos,
        'observacion': observacion,
        if (eliminadoPor != null) 'eliminado_por': eliminadoPor,
      };

  factory CargaEliminada.fromMap(Map<String, dynamic> map) {
    final pagosRaw = map['pagos'];
    final pagos = pagosRaw is List
        ? pagosRaw
            .map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.from(e as Map))
            .toList()
        : <Map<String, dynamic>>[];
    return CargaEliminada(
      id: map['id'],
      cargaId: map['carga_id'] ?? '',
      numero: map['numero'] ?? 0,
      proveedorId: map['proveedor_id'] ?? '',
      proveedorNombre: map['proveedor_nombre'] ?? '',
      fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
      cantidadAnimales: map['cantidad_animales'] ?? 0,
      kgVivo: (map['kg_vivo'] ?? 0).toDouble(),
      kgMediaRes:
          map['kg_media_res'] == null ? null : (map['kg_media_res']).toDouble(),
      totalAPagar: (map['total_a_pagar'] ?? 0).toDouble(),
      totalPagado: (map['total_pagado'] ?? 0).toDouble(),
      pagos: pagos,
      observacion: map['observacion'] ?? '',
      eliminadoEn:
          DateTime.tryParse(map['eliminado_en'] ?? '') ?? DateTime.now(),
      eliminadoPor: map['eliminado_por'],
    );
  }
}

// ─────────────────────────────────────────────
// PAGO DE CARGA ELIMINADO (audit log)
// ─────────────────────────────────────────────
class CargaPagoEliminado {
  final String id;
  final String pagoId;
  final String cargaId;
  final int cargaNumero;
  final String proveedorNombre;
  final DateTime fecha;
  final String medio;
  final double monto;
  final String observacion;
  final DateTime eliminadoEn;
  final String? eliminadoPor;

  CargaPagoEliminado({
    String? id,
    required this.pagoId,
    required this.cargaId,
    required this.cargaNumero,
    required this.proveedorNombre,
    required this.fecha,
    required this.medio,
    required this.monto,
    required this.observacion,
    DateTime? eliminadoEn,
    this.eliminadoPor,
  })  : id = id ?? _uuid.v4(),
        eliminadoEn = eliminadoEn ?? DateTime.now();

  String get cargaNumeroFormateado =>
      'PP-${cargaNumero.toString().padLeft(4, '0')}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'pago_id': pagoId,
        'carga_id': cargaId,
        'carga_numero': cargaNumero,
        'proveedor_nombre': proveedorNombre,
        'fecha': fecha.toIso8601String(),
        'medio': medio,
        'monto': monto,
        'observacion': observacion,
        if (eliminadoPor != null) 'eliminado_por': eliminadoPor,
      };

  factory CargaPagoEliminado.fromMap(Map<String, dynamic> map) =>
      CargaPagoEliminado(
        id: map['id'],
        pagoId: map['pago_id'] ?? '',
        cargaId: map['carga_id'] ?? '',
        cargaNumero: map['carga_numero'] ?? 0,
        proveedorNombre: map['proveedor_nombre'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        medio: map['medio'] ?? 'efectivo',
        monto: (map['monto'] ?? 0).toDouble(),
        observacion: map['observacion'] ?? '',
        eliminadoEn:
            DateTime.tryParse(map['eliminado_en'] ?? '') ?? DateTime.now(),
        eliminadoPor: map['eliminado_por'],
      );
}

// ─────────────────────────────────────────────
// CIERRE DE JORNADA DEL COBRADOR (v19.2)
// ─────────────────────────────────────────────
// Lo que un cobrador cobró en un día: cuánta plata y a qué clientes.
//
// DOS DECISIONES QUE CONVIENE NO TOCAR SIN PENSARLAS:
//
// 1. El día es el de `pago.fecha` (la fecha de cobro que eligió el cobrador),
//    NO el de `creado_en`. Es la misma fecha con la que trabajan el resto de
//    los reportes, y es la que el cobrador declara como día de cobranza. El
//    `creado_en` se muestra igual, como hora de carga de cada pago, porque es
//    lo que ordena la jornada y lo que delata un pago cargado al otro día.
//
// 2. Los montos son BRUTOS (`montoTotal`), no netos. La pregunta que contesta
//    el cierre es "cuánta plata cobró y a quién", y lo que el cobrador tiene
//    que rendir es la plata que recibió. El descuento interno del 6,2% de las
//    transferencias es un tema de ganancia, no de rendición, y ya está en el
//    tab de Ganancias.
//
// El número operativo del cierre es `efectivo`: es la plata que el cobrador
// trae encima y tiene que entregar. Lo que entró por transferencia o cheque
// no pasa por sus manos.

/// Un cobro de la jornada: el pago con el cliente y los medios ya resueltos.
class CobroJornada {
  final Pago pago;
  final String clienteNombre;
  final String? vendedorNombre;
  final List<PagoMedio> medios;

  const CobroJornada({
    required this.pago,
    required this.clienteNombre,
    this.vendedorNombre,
    this.medios = const [],
  });

  double get monto => pago.montoTotal;

  /// Hora de carga del pago (HH:MM), que es el orden real de la jornada.
  String get hora {
    final h = pago.creadoEn.hour.toString().padLeft(2, '0');
    final m = pago.creadoEn.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "Efectivo" / "Efectivo + Transferencia". Vacío si no se cargaron medios.
  String get mediosLabel => medios.map((m) => m.medioLabel).join(' + ');

  double porMedio(MedioPago medio) => medios
      .where((m) => m.medio == medio)
      .fold<double>(0, (s, m) => s + m.monto);

  /// El pago se cargó un día distinto al que dice cobrar.
  bool get cargadoOtroDia {
    final f = pago.fecha;
    final c = pago.creadoEn;
    return f.year != c.year || f.month != c.month || f.day != c.day;
  }
}

/// Resumen de la jornada de un cobrador en un día.
class ResumenJornada {
  final String cobrador;
  final DateTime dia;

  /// Cobros del día, en orden de carga (el recorrido tal como pasó).
  final List<CobroJornada> cobros;

  ResumenJornada({
    required this.cobrador,
    required DateTime dia,
    required List<CobroJornada> cobros,
  })  : dia = DateTime(dia.year, dia.month, dia.day),
        cobros = List.unmodifiable(
          [...cobros]
            ..sort((a, b) => a.pago.creadoEn.compareTo(b.pago.creadoEn)),
        );

  /// Total cobrado en el día (bruto).
  double get total => cobros.fold<double>(0, (s, c) => s + c.monto);

  /// Plata en mano que el cobrador tiene que rendir.
  double get efectivo => _porMedio(MedioPago.efectivo);
  double get transferencia => _porMedio(MedioPago.transferencia);
  double get cheque => _porMedio(MedioPago.cheque);

  double _porMedio(MedioPago medio) =>
      cobros.fold<double>(0, (s, c) => s + c.porMedio(medio));

  /// Lo repartido por medio puede no llegar al total si algún pago quedó sin
  /// medios cargados. Se expone para no inventar que el desglose cierra.
  double get sinDesglosar {
    final desglosado = efectivo + transferencia + cheque;
    final resto = total - desglosado;
    return resto.abs() < 0.01 ? 0 : resto;
  }

  bool get desgloseCompleto => sinDesglosar == 0;

  int get cantidadPagos => cobros.length;

  int get cantidadClientes =>
      cobros.map((c) => c.pago.clienteId).toSet().length;

  bool get vacia => cobros.isEmpty;
}

// ─────────────────────────────────────────────
// DEPÓSITO (v19.5) — stock de medias reses
// ─────────────────────────────────────────────
// Existe porque desde la cámara sacaron dos medias para un cliente, la cajera
// se olvidó de cargar el remito y nadie podía decir dónde estaban: plata
// perdida. El módulo cierra la ecuación entre lo comprado, lo distribuido a
// clientes y lo guardado en depósito.
//
// Nada del stock se persiste: se deriva de cargas + remitos + movimientos,
// igual que el saldo arrastrado del proveedor. Así, cargar un remito atrasado
// o corregir uno viejo reacomoda todo solo.

/// Un tercio de media res. Se escribe como fracción exacta y NO como 0,33
/// para que pierna + octavo + plancha de asado den exactamente una media:
/// con 0,33 tres cortes darían 0,99 y aparecerían diferencias fantasma.
const _tercio = 1 / 3;

/// Cuántas medias reses vale UNA unidad de cada tipo de carne del catálogo
/// de remitos (el campo del formulario se llama "Medias", pero cuando el tipo
/// es un corte esa unidad es el corte, no una media entera).
///
/// La media de novillo se divide en TRES partes: pierna, octavo y plancha de
/// asado. El "1/4 delantero" son dos de esos tercios (octavo + plancha).
const Map<String, double> equivalenciasMedia = {
  'Novillo': 1,
  'Cerdo': 1,
  'Pierna mocha': _tercio,
  'Pierna pistola': _tercio,
  'Plancha de asado': _tercio,
  'Octavo': _tercio,
  '1/4 delantero': 2 / 3,
};

/// La equivalencia de [tipoCarne], tolerante a mayúsculas y espacios.
///
/// Un tipo que no está en el catálogo cuenta como UNA media: es lo que dice
/// el campo del formulario y es el criterio conservador (de más, no de menos).
/// En la práctica no se usa: el stock arranca de cero en la fecha de
/// configuración y desde v18.17 los tipos salen de un dropdown fijo.
double equivalenciaEnMedias(String tipoCarne) {
  final buscado = tipoCarne.trim().toLowerCase();
  for (final entrada in equivalenciasMedia.entries) {
    if (entrada.key.toLowerCase() == buscado) return entrada.value;
  }
  return 1;
}

// ── Las partes de la media (v19.9) ──
// La media de novillo se parte en TRES: pierna, octavo y plancha de asado
// (el costillar completo). El cerdo no se fracciona: se vende entero.
//
// Esto no es lo mismo que la tabla de equivalencias de arriba. Ahí interesa
// CUÁNTA media vale un corte para que el stock cierre; acá interesa QUÉ
// PEDAZO es, para poder decir qué quedó suelto en la cámara: si se remitió
// una pierna, lo que queda para vender son un octavo y una plancha de asado.

const String partePierna = 'pierna';
const String parteOctavo = 'octavo';
const String partePlancha = 'plancha';

/// Qué partes de la media se lleva un tipo de carne del catálogo de remitos.
///
/// Una media entera (`Novillo`, `Cerdo`) no abre nada y devuelve vacío. El
/// `1/4 delantero` se lleva DOS partes de la misma media: el octavo y la
/// plancha de asado.
List<String> partesDeCorte(String tipoCarne) {
  final t = tipoCarne.trim().toLowerCase();
  if (t.contains('pierna')) return const [partePierna];
  if (t.contains('octavo')) return const [parteOctavo];
  if (t.contains('plancha')) return const [partePlancha];
  if (t.contains('delantero')) return const [parteOctavo, partePlancha];
  return const [];
}

/// Los cortes que salieron del depósito, para poder decir qué quedó suelto.
///
/// Cada vez que se vende una pierna y no hay ninguna suelta hay que ABRIR una
/// media, y el octavo y la plancha de esa media quedan disponibles. Como cada
/// media abierta deja exactamente una parte de cada clase, alcanza con contar
/// cuántas se pidieron de cada una: las medias que hubo que abrir son el
/// máximo de las tres, y lo suelto es lo que sobra de ese máximo.
///
/// La cuenta cierra con el stock en medias sin trucos: las medias enteras más
/// las partes sueltas (un tercio cada una) dan exactamente el stock teórico.
class CortesVendidos {
  final int piernas;
  final int octavos;
  final int planchas;

  const CortesVendidos({
    this.piernas = 0,
    this.octavos = 0,
    this.planchas = 0,
  });

  /// Cuántas medias hubo que abrir para servir esos cortes.
  int get mediasAbiertas =>
      [piernas, octavos, planchas].reduce((a, b) => a > b ? a : b);

  int get piernasSueltas => mediasAbiertas - piernas;
  int get octavosSueltos => mediasAbiertas - octavos;
  int get planchasSueltas => mediasAbiertas - planchas;

  int get totalSueltas => piernasSueltas + octavosSueltos + planchasSueltas;

  bool get haySueltas => totalSueltas > 0;

  /// Lo suelto medido en medias: cada parte es un tercio.
  double get sueltasEnMedias => totalSueltas * _tercio;
}

/// El nombre de una parte, en singular o plural: "1 octavo", "2 piernas",
/// "1 plancha de asado".
String labelParte(String parte, int cantidad) {
  final plural = cantidad != 1;
  return switch (parte) {
    partePierna => plural ? 'piernas' : 'pierna',
    parteOctavo => plural ? 'octavos' : 'octavo',
    _ => plural ? 'planchas de asado' : 'plancha de asado',
  };
}

/// A qué stock le pega un tipo de carne: [Proveedor.tipoNovillo] o
/// [Proveedor.tipoCerdo]. Solo "Cerdo" es cerdo; todo el resto (novillo y sus
/// cinco cortes) computa como novillo. Es la misma regla que `_normalizarTipo`
/// en app_provider y `costoPorTipo` en [CostoSemanal].
String stockDeTipoCarne(String tipoCarne) =>
    tipoCarne.trim().toLowerCase().contains('cerdo')
        ? Proveedor.tipoCerdo
        : Proveedor.tipoNovillo;

/// Cuántas medias reses sale de un animal en pie: una res se parte al medio.
const int mediasPorAnimal = 2;

/// Margen con el que se considera que los números "dan redondos".
///
/// Hace falta por los tercios: en coma flotante 1/3 + 1/3 + 1/3 no da
/// exactamente 1, y la BD guarda los movimientos con cuatro decimales. Sin
/// este margen, una diferencia de 0,0000000001 media encendería la alerta.
const double toleranciaMedias = 0.02;

/// Lee la columna JSONB `kgs_por_media`. Tolera que no venga (se agregó en
/// v19.6, con el módulo ya en producción) y que traiga basura: en los dos
/// casos devuelve lista vacía en vez de romper la pantalla.
List<double> _leerKgs(dynamic valor) {
  if (valor is! List) return [];
  final kgs = <double>[];
  for (final e in valor) {
    if (e is num) kgs.add(e.toDouble());
  }
  return kgs;
}

/// Configuración del arranque del depósito: una sola fila.
///
/// El sistema tiene remitos de hace meses pero cargas de proveedores recién
/// desde el 20/10/2026, así que contar "desde siempre" daría cualquier cosa.
/// Por eso el depósito arranca de cero en una fecha elegida: se cuenta a mano
/// lo que hay en la cámara ese día y de ahí en adelante manda la ecuación.
class DepositoConfig {
  final String id;
  DateTime fechaInicio;
  double mediasNovillo;
  double mediasCerdo;

  /// Lo que pesaban esas medias (v19.9). Opcionales, como todos los kilos del
  /// módulo: si no hay balanza a mano el arranque se guarda igual y el kilaje
  /// del stock queda marcado como incompleto.
  double kgNovillo;
  double kgCerdo;

  String? registradoPor;
  DateTime actualizadoEn;

  DepositoConfig({
    String? id,
    DateTime? fechaInicio,
    this.mediasNovillo = 0,
    this.mediasCerdo = 0,
    this.kgNovillo = 0,
    this.kgCerdo = 0,
    this.registradoPor,
    DateTime? actualizadoEn,
  })  : id = id ?? _uuid.v4(),
        fechaInicio = fechaInicio ?? DateTime.now(),
        actualizadoEn = actualizadoEn ?? DateTime.now();

  /// Las medias que había en la cámara el día del arranque, por tipo.
  double inicialDe(String tipo) =>
      tipo == Proveedor.tipoCerdo ? mediasCerdo : mediasNovillo;

  /// Los kilos de esas medias. 0 cuando no se pesaron.
  double kgInicialDe(String tipo) =>
      tipo == Proveedor.tipoCerdo ? kgCerdo : kgNovillo;

  Map<String, dynamic> toMap() => {
        'id': id,
        // Va explícito para poder hacer upsert sobre la columna UNIQUE que
        // garantiza que exista una sola fila de configuración.
        'unica': true,
        'fecha_inicio': fechaInicio.toIso8601String(),
        'medias_novillo': mediasNovillo,
        'medias_cerdo': mediasCerdo,
        'kg_novillo': kgNovillo,
        'kg_cerdo': kgCerdo,
        'registrado_por': registradoPor,
        'actualizado_en': actualizadoEn.toIso8601String(),
      };

  factory DepositoConfig.fromMap(Map<String, dynamic> map) => DepositoConfig(
        id: map['id'],
        fechaInicio: DateTime.tryParse(map['fecha_inicio'] ?? ''),
        mediasNovillo: (map['medias_novillo'] ?? 0).toDouble(),
        mediasCerdo: (map['medias_cerdo'] ?? 0).toDouble(),
        // Toleran que las columnas no existan: se agregaron en v19.9, con el
        // módulo ya en producción.
        kgNovillo: (map['kg_novillo'] ?? 0).toDouble(),
        kgCerdo: (map['kg_cerdo'] ?? 0).toDouble(),
        registradoPor: map['registrado_por'],
        actualizadoEn: DateTime.tryParse(map['actualizado_en'] ?? ''),
      );
}

/// Un movimiento de depósito cargado a mano. Las tres clases son cosas
/// distintas, no variantes de lo mismo — ver [claseEntrada], [claseSalida] y
/// [claseRecuento]. `medias` va siempre en positivo: el signo lo pone la clase.
class DepositoMovimiento {
  /// Medias que entran al depósito SIN venir de una carga: una devolución de
  /// un cliente o un ajuste a favor. La compra al proveedor NO necesita una
  /// entrada, ya suma sola por la ecuación.
  static const claseEntrada = 'entrada';

  /// Medias que salieron de la cámara. Es el botón que aprieta la cajera
  /// cuando saca carne y todavía no cargó el remito: con [esperaRemito] en
  /// true la salida queda pendiente y se cierra sola cuando aparece un remito
  /// de ese tipo. En false es definitiva (merma, consumo propio, rotura).
  static const claseSalida = 'salida';

  /// No mueve nada: es la foto de lo que se contó físicamente en la cámara,
  /// para comparar contra el stock teórico de ese momento.
  static const claseRecuento = 'recuento';

  final String id;
  int numero; // lo asigna la secuencia de Postgres => D-0001
  String tipo; // Proveedor.tipoNovillo / tipoCerdo
  String clase;
  double medias;

  /// Un kilo por cada media, igual que `NotaPedidoItem.kgsPorMedia`: un array
  /// y no un total, porque dos medias pueden diferenciarse en 40 kg y lo que
  /// importa es saber cuál salió y cuál entró.
  ///
  /// **Son opcionales y pueden venir incompletos.** Si el campo frenara el
  /// registro cuando la cajera no tiene la balanza a mano, no registraría la
  /// salida — que es justo el agujero que este módulo vino a tapar. Por eso
  /// nada valida que la lista tenga tantos valores como [medias].
  ///
  /// **Son informativos**: la ecuación del depósito cierra por MEDIAS. Los
  /// kilos se muestran, pero no disparan la alerta de faltantes.
  List<double> kgsPorMedia;

  bool esperaRemito;
  DateTime fecha;
  String observacion;
  String? registradoPor;
  final DateTime creadoEn;

  DepositoMovimiento({
    String? id,
    this.numero = 0,
    this.tipo = Proveedor.tipoNovillo,
    required this.clase,
    this.medias = 0,
    List<double>? kgsPorMedia,
    this.esperaRemito = true,
    DateTime? fecha,
    this.observacion = '',
    this.registradoPor,
    DateTime? creadoEn,
  })  : id = id ?? _uuid.v4(),
        kgsPorMedia = kgsPorMedia ?? [],
        fecha = fecha ?? DateTime.now(),
        creadoEn = creadoEn ?? DateTime.now();

  /// La suma de los kilos cargados. No se guarda en la base: se deriva, como
  /// todo lo demás de este módulo.
  double get totalKg => kgsPorMedia.fold<double>(0, (t, kg) => t + kg);

  bool get tieneKg => kgsPorMedia.isNotEmpty;

  /// Cuántas medias quedaron sin pesar. Sirve para avisar que el dato está a
  /// medias, sin bloquear nada.
  int get mediasSinPesar {
    final faltan = medias.ceil() - kgsPorMedia.length;
    return faltan > 0 ? faltan : 0;
  }

  bool get esEntrada => clase == claseEntrada;
  bool get esSalida => clase == claseSalida;
  bool get esRecuento => clase == claseRecuento;

  /// Una salida que todavía espera su remito. Es lo que la pantalla muestra
  /// como "medias que salieron sin registrar".
  bool get esSalidaPendienteDeRemito => esSalida && esperaRemito;

  /// Una salida que nunca va a tener remito: merma, consumo propio o rotura.
  /// Descuenta del stock para siempre.
  bool get esSalidaDefinitiva => esSalida && !esperaRemito;

  String get numeroFormateado => 'D-${numero.toString().padLeft(4, '0')}';

  String get tipoLabel => tipo == Proveedor.tipoCerdo ? 'Cerdo' : 'Novillo';

  String get claseLabel => switch (clase) {
        claseEntrada => 'Entrada',
        claseSalida => 'Salida',
        _ => 'Recuento',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        // numero lo pone la secuencia: si va en 0 no se manda
        if (numero > 0) 'numero': numero,
        'tipo': tipo,
        'clase': clase,
        'medias': medias,
        'kgs_por_media': kgsPorMedia,
        'espera_remito': esperaRemito,
        'fecha': fecha.toIso8601String(),
        'observacion': observacion,
        'registrado_por': registradoPor,
        'creado_en': creadoEn.toIso8601String(),
      };

  factory DepositoMovimiento.fromMap(Map<String, dynamic> map) =>
      DepositoMovimiento(
        id: map['id'],
        numero: map['numero'] ?? 0,
        tipo: '${map['tipo']}'.toLowerCase().contains('cerdo')
            ? Proveedor.tipoCerdo
            : Proveedor.tipoNovillo,
        clase: map['clase'] ?? claseEntrada,
        medias: (map['medias'] ?? 0).toDouble(),
        kgsPorMedia: _leerKgs(map['kgs_por_media']),
        esperaRemito: map['espera_remito'] ?? true,
        fecha: DateTime.tryParse(map['fecha'] ?? ''),
        observacion: map['observacion'] ?? '',
        registradoPor: map['registrado_por'],
        creadoEn: DateTime.tryParse(map['creado_en'] ?? ''),
      );
}

/// Auditoría de un movimiento borrado. `observacion` es obligatoria: un
/// movimiento borrado sin motivo sería justamente el agujero que este módulo
/// vino a tapar.
class DepositoMovimientoEliminado {
  final String id;
  final String movimientoId;
  final int movimientoNumero;
  final String tipo;
  final String clase;
  final double medias;
  final List<double> kgsPorMedia;
  final bool esperaRemito;
  final DateTime fecha;
  final String observacionOriginal;
  final String observacion;
  final DateTime eliminadoEn;
  final String? eliminadoPor;

  DepositoMovimientoEliminado({
    String? id,
    required this.movimientoId,
    this.movimientoNumero = 0,
    this.tipo = Proveedor.tipoNovillo,
    this.clase = DepositoMovimiento.claseEntrada,
    this.medias = 0,
    List<double>? kgsPorMedia,
    this.esperaRemito = true,
    DateTime? fecha,
    this.observacionOriginal = '',
    required this.observacion,
    DateTime? eliminadoEn,
    this.eliminadoPor,
  })  : id = id ?? _uuid.v4(),
        kgsPorMedia = kgsPorMedia ?? const [],
        fecha = fecha ?? DateTime.now(),
        eliminadoEn = eliminadoEn ?? DateTime.now();

  /// Arma la fila de auditoría a partir del movimiento que se va a borrar.
  factory DepositoMovimientoEliminado.desde(
    DepositoMovimiento mov, {
    required String observacion,
    String? eliminadoPor,
  }) =>
      DepositoMovimientoEliminado(
        movimientoId: mov.id,
        movimientoNumero: mov.numero,
        tipo: mov.tipo,
        clase: mov.clase,
        medias: mov.medias,
        kgsPorMedia: mov.kgsPorMedia,
        esperaRemito: mov.esperaRemito,
        fecha: mov.fecha,
        observacionOriginal: mov.observacion,
        observacion: observacion,
        eliminadoPor: eliminadoPor,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'movimiento_id': movimientoId,
        'movimiento_numero': movimientoNumero,
        'tipo': tipo,
        'clase': clase,
        'medias': medias,
        'kgs_por_media': kgsPorMedia,
        'espera_remito': esperaRemito,
        'fecha': fecha.toIso8601String(),
        'observacion_original': observacionOriginal,
        'observacion': observacion,
        'eliminado_en': eliminadoEn.toIso8601String(),
        'eliminado_por': eliminadoPor,
      };

  factory DepositoMovimientoEliminado.fromMap(Map<String, dynamic> map) =>
      DepositoMovimientoEliminado(
        id: map['id'],
        movimientoId: map['movimiento_id'] ?? '',
        movimientoNumero: map['movimiento_numero'] ?? 0,
        tipo: map['tipo'] ?? Proveedor.tipoNovillo,
        clase: map['clase'] ?? DepositoMovimiento.claseEntrada,
        medias: (map['medias'] ?? 0).toDouble(),
        kgsPorMedia: _leerKgs(map['kgs_por_media']),
        esperaRemito: map['espera_remito'] ?? true,
        fecha: DateTime.tryParse(map['fecha'] ?? ''),
        observacionOriginal: map['observacion_original'] ?? '',
        observacion: map['observacion'] ?? '',
        eliminadoEn: DateTime.tryParse(map['eliminado_en'] ?? ''),
        eliminadoPor: map['eliminado_por'],
      );
}

/// El resultado de la ecuación del depósito para UN tipo (novillo o cerdo).
///
/// Es un valor calculado al vuelo por `AppProvider.stockDeposito`: no hay
/// tabla que lo guarde. Los componentes están expuestos uno por uno porque la
/// pantalla los muestra desglosados — si Joaco no puede ver de dónde sale cada
/// número, no le va a creer a la alerta.
class StockDeposito {
  final String tipo;

  // ── Componentes a HOY ──
  /// Lo que había en la cámara el día del arranque (ver [DepositoConfig]).
  final double inicial;

  /// Medias que entraron por compras a proveedores: animales × 2.
  final double compradas;

  /// Entradas manuales: devoluciones de clientes y ajustes a favor.
  final double entradas;

  /// Medias que salieron a clientes con remito CONFIRMADO, ya convertidas por
  /// la tabla de equivalencias (un remito de 3 piernas descuenta 1 media).
  final double remitidas;

  /// Salidas que todavía esperan su remito: la carne ya no está en la cámara
  /// pero nadie la facturó. Es exactamente el agujero que motivó el módulo.
  final double salidasPendientes;

  /// Salidas que nunca van a tener remito: merma, consumo propio, rotura.
  final double salidasDefinitivas;

  // ── El recuento físico y su comparación ──
  /// Lo último que se contó a mano en la cámara. Null si nunca se contó.
  final double? recuento;
  final DateTime? fechaRecuento;

  /// Los kilos de ese recuento, si se pesaron. Es el único kg "de stock" que
  /// se puede mostrar honestamente: los kilos NO se reconcilian como las
  /// medias, así que no hay un kg teórico que valga la pena mostrar.
  final double kgRecuento;

  /// El stock teórico que correspondía EN EL MOMENTO del recuento.
  ///
  /// La comparación se hace contra este valor y no contra [teorico], porque si
  /// no cualquier compra posterior al último recuento aparecería como un
  /// faltante gigante: se cuenta 10 el viernes, el lunes entra una carga de
  /// 200 y el sistema gritaría "faltan 200 medias".
  final double? teoricoAlRecuento;

  /// Las salidas todavía sin remito, para poder listarlas y avisar cuál es.
  final List<DepositoMovimiento> pendientes;

  // ── Los kilos de cada componente (v19.9) ──
  // Misma ecuación que las medias, pero en peso. Son INFORMATIVOS: el
  // veredicto de faltantes sigue saliendo de las medias. Sirven para la
  // pregunta que las medias no contestan: cuánta carne hay en la cámara,
  // porque dos medias pueden diferenciarse en 40 kg.
  //
  // Pueden venir incompletos (una carga sin faena, una salida sin pesar).
  // [mediasSinPesar] dice cuántas medias de esta cuenta no tienen kilos, para
  // que el número se muestre como lo que es y no como una verdad.
  final double kgInicial;
  final double kgComprados;
  final double kgEntradas;
  final double kgRemitidos;
  final double kgSalidasPendientes;
  final double kgSalidasDefinitivas;

  /// Medias de esta cuenta que nadie pesó. > 0 = el kilaje está incompleto.
  final double mediasSinPesar;

  /// Los cortes que salieron, para saber qué quedó suelto en la cámara
  /// (v19.9). En cerdo va siempre vacío: no se fracciona.
  final CortesVendidos cortes;

  const StockDeposito({
    required this.tipo,
    this.inicial = 0,
    this.compradas = 0,
    this.entradas = 0,
    this.remitidas = 0,
    this.salidasPendientes = 0,
    this.salidasDefinitivas = 0,
    this.recuento,
    this.fechaRecuento,
    this.kgRecuento = 0,
    this.teoricoAlRecuento,
    this.pendientes = const [],
    this.kgInicial = 0,
    this.kgComprados = 0,
    this.kgEntradas = 0,
    this.kgRemitidos = 0,
    this.kgSalidasPendientes = 0,
    this.kgSalidasDefinitivas = 0,
    this.mediasSinPesar = 0,
    this.cortes = const CortesVendidos(),
  });

  String get tipoLabel => tipo == Proveedor.tipoCerdo ? 'Cerdo' : 'Novillo';

  /// Las medias que deberían estar físicamente en la cámara ahora mismo.
  double get teorico =>
      inicial +
      compradas +
      entradas -
      remitidas -
      salidasPendientes -
      salidasDefinitivas;

  /// Total comprado + lo que ya había + devoluciones: el lado de las entradas.
  /// Es el "disponible para vender" del que habla el circuito: una compra
  /// nueva se suma a las medias que ya estaban en depósito sin vender.
  double get totalDisponible => inicial + compradas + entradas;

  bool get tieneRecuento => recuento != null && teoricoAlRecuento != null;

  /// Positivo = faltan medias en la cámara (salieron sin registrar).
  /// Negativo = hay medias de más que el sistema no conoce.
  /// Null = todavía no se contó nada, no hay con qué comparar.
  double? get diferencia =>
      tieneRecuento ? teoricoAlRecuento! - recuento! : null;

  /// true cuando los números dan redondos (dentro de [toleranciaMedias]).
  bool get cierra => tieneRecuento && diferencia!.abs() <= toleranciaMedias;

  bool get faltan => (diferencia ?? 0) > toleranciaMedias;
  bool get sobran => (diferencia ?? 0) < -toleranciaMedias;

  /// Cuántas medias faltan (0 si no faltan). Es el número de la alerta.
  double get faltantes => faltan ? diferencia! : 0;

  /// Cuántas medias hay de más (0 si no sobran).
  double get sobrantes => sobran ? -diferencia! : 0;

  bool get hayPendientes => pendientes.isNotEmpty;

  /// Los kilos que salieron del depósito y todavía no tienen remito.
  double get kgPendientes =>
      pendientes.fold<double>(0, (t, m) => t + m.totalKg);

  // ── Kilos y partes de lo que hay en la cámara (v19.9) ──

  /// Los kilos que deberían estar en la cámara ahora mismo, por la misma
  /// ecuación que [teorico] pero en peso. Nunca baja de cero: con los kilos
  /// incompletos un negativo no sería un faltante real, solo lo que falta
  /// pesar.
  double get kgTeorico {
    final kg = kgInicial +
        kgComprados +
        kgEntradas -
        kgRemitidos -
        kgSalidasPendientes -
        kgSalidasDefinitivas;
    return kg > 0 ? kg : 0;
  }

  /// true cuando hay medias sin pesar en la cuenta: el kilaje es parcial.
  bool get kgIncompleto => mediasSinPesar > toleranciaMedias;

  /// true cuando hay algún kilo que mostrar. Sin esto la pantalla mostraría
  /// un "0 kg" que no significa "la cámara está vacía" sino "nadie pesó".
  bool get tieneKg => kgTeorico > 0;

  /// Lo que quedó suelto de las medias que se abrieron, en medias.
  double get mediasSueltas => cortes.sueltasEnMedias;

  /// Las medias que siguen enteras en la cámara. El resto del stock son las
  /// partes sueltas: [mediasEnteras] + [mediasSueltas] = [teorico].
  double get mediasEnteras {
    final enteras = teorico - mediasSueltas;
    return enteras > 0 ? enteras : 0;
  }

  bool get hayPartesSueltas => cortes.haySueltas;
}

// ─────────────────────────────────────────────
// DESGLOSE DE LO VENDIDO EN LA SEMANA (v19.10)
// ─────────────────────────────────────────────
// Lo que hay detrás del número grande de kg del dashboard: a qué clientes se
// les vendió esa carne, cuántas medias se llevó cada uno y por cuánta plata.
//
// DOS DECISIONES:
//
// 1. Los kg, las medias y el importe son SOLO los del tipo consultado. Un
//    remito puede traer novillo y cerdo juntos; si el desglose de novillo
//    sumara el remito entero, la suma de la pantalla no daría el número de
//    la tarjeta que se tocó. El total de la factura se muestra aparte, en
//    los remitos mezclados, que son los únicos donde los dos difieren.
//
// 2. El importe sale de los items (`kg × precio/kg`), igual que el kg; el
//    total de la factura sale de `remito.totalPesos`, que es lo que figura
//    en el remito del cliente.

/// Un remito de la semana, visto desde un solo tipo de carne.
class VentaRemitoSemana {
  final Remito remito;

  /// Medias, kg e importe del tipo consultado (no del remito entero).
  final int medias;
  final double kg;
  final double importe;

  /// El remito trae además items de otro tipo de carne.
  final bool tieneOtrosTipos;

  const VentaRemitoSemana({
    required this.remito,
    required this.medias,
    required this.kg,
    required this.importe,
    this.tieneOtrosTipos = false,
  });

  /// El total de la factura, con todos los tipos de carne.
  double get totalFactura => remito.totalPesos;
}

/// Lo que se llevó un cliente en la semana, de un tipo de carne.
class VentaClienteSemana {
  final String clienteId;
  final String clienteNombre;
  final String? vendedorNombre;
  final List<VentaRemitoSemana> remitos;

  VentaClienteSemana({
    required this.clienteId,
    required this.clienteNombre,
    this.vendedorNombre,
    required List<VentaRemitoSemana> remitos,
  }) : remitos = List.unmodifiable(
          [...remitos]..sort((a, b) {
              final porFecha = a.remito.fecha.compareTo(b.remito.fecha);
              return porFecha != 0
                  ? porFecha
                  : a.remito.numero.compareTo(b.remito.numero);
            }),
        );

  int get medias => remitos.fold<int>(0, (s, r) => s + r.medias);
  double get kg => remitos.fold<double>(0, (s, r) => s + r.kg);
  double get importe => remitos.fold<double>(0, (s, r) => s + r.importe);

  /// Lo facturado en total (todos los tipos) en los remitos que lo tocaron.
  double get totalFacturado =>
      remitos.fold<double>(0, (s, r) => s + r.totalFactura);

  bool get hayRemitosMezclados => remitos.any((r) => r.tieneOtrosTipos);

  int get cantidadRemitos => remitos.length;
}

/// El desglose completo de un tipo de carne en una semana.
class DesgloseSemanaTipo {
  /// 'Novillo' o 'Cerdo', ya normalizado.
  final String tipo;
  final DateTime semanaInicio;

  /// Clientes de mayor a menor kg: el desglose se lee para saber a dónde
  /// se fue la carne, y lo primero que se busca es quién se llevó más.
  final List<VentaClienteSemana> clientes;

  DesgloseSemanaTipo({
    required this.tipo,
    required DateTime semanaInicio,
    required List<VentaClienteSemana> clientes,
  })  : semanaInicio =
            DateTime(semanaInicio.year, semanaInicio.month, semanaInicio.day),
        clientes = List.unmodifiable(
          [...clientes]..sort((a, b) {
              final porKg = b.kg.compareTo(a.kg);
              return porKg != 0
                  ? porKg
                  : compararNombres(a.clienteNombre, b.clienteNombre);
            }),
        );

  int get medias => clientes.fold<int>(0, (s, c) => s + c.medias);
  double get kg => clientes.fold<double>(0, (s, c) => s + c.kg);
  double get importe => clientes.fold<double>(0, (s, c) => s + c.importe);

  int get cantidadClientes => clientes.length;
  int get cantidadRemitos =>
      clientes.fold<int>(0, (s, c) => s + c.cantidadRemitos);

  bool get vacio => clientes.isEmpty;
}
