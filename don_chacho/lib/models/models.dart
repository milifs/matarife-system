// ============================================================
// MODELOS DE DATOS - Granja Don Chacho - Matarife Terceros
// ============================================================
// Cada modelo mapea 1:1 con las tablas de Supabase (PostgreSQL)
// y contiene la lógica de serialización/deserialización.
// ============================================================

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

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

  Pago({
    String? id,
    required this.clienteId,
    required this.fecha,
    this.numero = 0,
    required this.montoTotal,
    required this.netoRecibido,
    DateTime? creadoEn,
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
      };

  factory Pago.fromMap(Map<String, dynamic> map) => Pago(
        id: map['id'],
        clienteId: map['cliente_id'] ?? '',
        fecha: DateTime.tryParse(map['fecha'] ?? '') ?? DateTime.now(),
        numero: map['numero'] ?? 0,
        montoTotal: (map['monto_total'] ?? 0).toDouble(),
        netoRecibido: (map['neto_recibido'] ?? 0).toDouble(),
        creadoEn: DateTime.tryParse(map['creado_en'] ?? '') ?? DateTime.now(),
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
        netoRecibido = medio == MedioPago.transferencia
            ? monto * (1 - 0.062)
            : monto;

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
        costoPorKgNovillo: (map['costo_por_kg_novillo'] ?? map['costo_por_kg'] ?? 0).toDouble(),
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
  String descripcion;
  int cantidadMedias;
  List<double> kgsPorMedia; // un valor por cada media
  double precioPorMedia;

  NotaPedidoItem({
    String? id,
    required this.notaPedidoId,
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

  String get numeroFormateado =>
      'NP-${numero.toString().padLeft(4, '0')}';

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
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
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

  bool tienePermiso(String permisoId) => esAdmin || permisoIds.contains(permisoId);

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
