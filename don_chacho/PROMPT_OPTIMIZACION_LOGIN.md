# Prompt para Claude Code — Optimizar la carga post-login (Don Chacho)

Copiá todo lo que está debajo de la línea `---` y pegalo como mensaje a Claude Code dentro de la carpeta `C:\App Joaco\don_chacho_v17\don_chacho`.

---

# Tarea: Optimizar la carga de datos después del login

La app es Flutter Web + Supabase. Hoy, después de loguearse, el usuario espera 15+ segundos a que aparezca la pantalla principal. Identifiqué tres causas y quiero que las arregles. No toques nada que no esté listado acá. No modifiques pantallas (`lib/screens/*`) ni `pubspec.yaml` ni los `.sql`.

## Problema 1 — N+1 en items de remito (el peor)

En `lib/providers/app_provider.dart`, dentro de `cargarDatos()` (alrededor de la línea 115), existe este loop:

```dart
_remitoItems.clear();
for (final remito in _remitos) {
  _remitoItems[remito.id] = await _db.getRemitoItems(remito.id);
}
```

Si hay 300 remitos, hace 300 viajes secuenciales a Supabase. Hay que reemplazarlo por **una sola query** que traiga todos los items y después se agrupan en memoria.

### Cambios concretos

**1.a** — En `lib/services/database_service.dart`, agregá un método nuevo después de `getRemitoItems` (línea ~177):

```dart
/// Trae los items de TODOS los remitos en una sola query.
/// Se agrupan en memoria por remito_id en el caller.
Future<List<RemitoItem>> getAllRemitoItems() async {
  final data = await _client.from('remito_items').select();
  return data.map((e) => RemitoItem.fromMap(e)).toList();
}
```

**1.b** — En `lib/providers/app_provider.dart`, dentro de `cargarDatos()`, reemplazá el bloque del loop (las 4 líneas del `for`) por:

```dart
_remitoItems.clear();
final allItems = await _db.getAllRemitoItems();
for (final item in allItems) {
  _remitoItems.putIfAbsent(item.remitoId, () => []).add(item);
}
```

Eso convierte N queries en 1 sola.

## Problema 2 — N+1 en items de notas de pedido

En `lib/services/database_service.dart`, el método `getNotasPedido()` (línea ~327) tiene el mismo patrón:

```dart
Future<List<NotaPedido>> getNotasPedido() async {
  final data = await _client.from('notas_pedido').select()...;
  final ndps = <NotaPedido>[];
  for (final row in data) {
    final itemsData = await _client.from('nota_pedido_items').select()
        .eq('nota_pedido_id', row['id']);
    ...
  }
  return ndps;
}
```

Reemplazá el cuerpo entero del método por una versión que hace **dos queries totales** (una para cabeceras, una para todos los items) y agrupa en memoria:

```dart
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
```

## Problema 3 — Las 8 queries iniciales están en serie

En `lib/providers/app_provider.dart`, dentro de `cargarDatos()`, hoy se ejecutan así (cada una espera a la anterior):

```dart
_vendedores = await _db.getVendedores();
_clientes = await _db.getClientes();
_remitos = await _db.getRemitos();
_pagos = await _db.getPagos();
_pagosEliminados = await _db.getPagosEliminados();
_notasPedido = await _db.getNotasPedido();
_costoSemanaActual = await _db.getCostoSemana(DateTime.now());
_costosSemanales = await _db.getAllCostosSemana();
```

Reemplazá ese bloque por una versión en paralelo con `Future.wait`, manteniendo el orden de asignación a las variables:

```dart
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
```

Después de ese bloque viene la carga de `_remitoItems` (lo que arreglaste en el Problema 1) y `_recalcularSaldos()`.

**Importante:** los items de remito (Problema 1) **se deben cargar después** de tener `_remitos`, así que no los metas dentro del `Future.wait` ese. Quedan como una llamada separada inmediatamente después.

## Resultado final esperado del método `cargarDatos()`

Después de los tres cambios, el método debe quedar así (estructura, no copies texto literal si el resto del archivo cambió):

```dart
Future<void> cargarDatos() async {
  _loading = true;
  _error = null;
  notifyListeners();

  try {
    // 1) Las 8 cargas principales en paralelo
    final results = await Future.wait([ ... 8 futures ... ]);
    _vendedores = results[0] as List<Vendedor>;
    // ... resto de asignaciones ...

    // 2) Items de remito en UNA query, agrupados en memoria
    _remitoItems.clear();
    final allItems = await _db.getAllRemitoItems();
    for (final item in allItems) {
      _remitoItems.putIfAbsent(item.remitoId, () => []).add(item);
    }

    // 3) Saldos
    await _recalcularSaldos();

    _loading = false;
    notifyListeners();
  } catch (e) {
    _loading = false;
    _error = e.toString();
    notifyListeners();
  }
}
```

## Paso final — Agregar índices en Supabase

Para que las queries sean rápidas del lado del servidor, generá un archivo nuevo `supabase_migration_indices.sql` en la raíz del proyecto (al lado de los otros `.sql` que ya hay) con este contenido:

```sql
-- Índices para mejorar la performance de carga inicial
-- Ejecutar UNA SOLA VEZ en el SQL Editor de Supabase.

CREATE INDEX IF NOT EXISTS idx_remito_items_remito_id
  ON remito_items(remito_id);

CREATE INDEX IF NOT EXISTS idx_nota_pedido_items_nota_id
  ON nota_pedido_items(nota_pedido_id);

CREATE INDEX IF NOT EXISTS idx_pago_medios_pago_id
  ON pago_medios(pago_id);

CREATE INDEX IF NOT EXISTS idx_remitos_estado
  ON remitos(estado);

CREATE INDEX IF NOT EXISTS idx_remitos_fecha_desc
  ON remitos(fecha DESC);

CREATE INDEX IF NOT EXISTS idx_pagos_fecha_desc
  ON pagos(fecha DESC);
```

En el archivo dejá un comentario arriba que diga: `-- Ejecutar este script una vez en Supabase Dashboard > SQL Editor para acelerar la carga inicial.`

## Verificación

Cuando termines:

1. Confirmá que `database_service.dart` compila (sin errores de tipo).
2. Confirmá que `app_provider.dart` compila.
3. Decime qué archivos modificaste y cuáles creaste.
4. Pasame las instrucciones literales para correr la migración: "Andá a Supabase > SQL Editor > pegá el contenido de `supabase_migration_indices.sql` > Run".
5. Recordame que después de los cambios tengo que correr `build_web.bat` para regenerar la build de producción.

## Restricciones

- No toques `lib/screens/*`, `lib/models/*`, `pubspec.yaml`, ni los archivos `.sql` ya existentes.
- No agregues paquetes nuevos al `pubspec.yaml`.
- Mantené el estilo de código y los comentarios del proyecto (todo en español).
- Si encontrás que alguna línea referenciada no está exactamente como la describí (porque el archivo cambió), aplicá el cambio igual usando el contexto, no me preguntes.
