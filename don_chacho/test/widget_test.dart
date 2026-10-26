// Este archivo venía del scaffold de `flutter create`: probaba el contador de
// la app de ejemplo y pumpeaba una clase `MyApp` que nunca existió en este
// proyecto (la raíz es `DonChachoApp`). No compilaba, así que `flutter test`
// daba rojo entero y tapaba cualquier regresión real de los otros archivos.
//
// Pumpear `DonChachoApp` tampoco sirve como smoke test: construye un
// `AppProvider` (que instancia `DatabaseService` → `Supabase.instance.client`)
// y `AppWrapper.initState` llama a `AuthService.restaurarSesion()`. Las dos
// cosas revientan sin un `Supabase.initialize`, y con él el test saldría a la
// red contra la base de producción.
//
// Así que acá se prueba lo que sí se puede probar sin red: `StatusPill`, el
// widget compartido que pinta los estados en media app (remitos, notas de
// pedido, soporte, proveedores). Lo que se protege es el mapeo tipo → colores:
// que un estado de error no termine pintado de verde.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:don_chacho_matarife/utils/theme.dart';

void main() {
  // Envuelve el widget en lo mínimo para que tenga Directionality y tema.
  Widget conApp(Widget child) =>
      MaterialApp(theme: AppTheme.theme, home: Scaffold(body: child));

  group('StatusPill', () {
    testWidgets('muestra el texto que se le pasa', (tester) async {
      await tester.pumpWidget(
        conApp(const StatusPill(text: 'Confirmado', type: StatusType.success)),
      );
      expect(find.text('Confirmado'), findsOneWidget);
    });

    testWidgets('cada tipo pinta su par de colores', (tester) async {
      const esperado = {
        StatusType.success: (AppTheme.successBg, AppTheme.success),
        StatusType.warning: (AppTheme.warningBg, AppTheme.warning),
        StatusType.danger: (AppTheme.dangerBg, AppTheme.danger),
        StatusType.info: (AppTheme.infoBg, AppTheme.info),
      };

      for (final entrada in esperado.entries) {
        final (fondo, letra) = entrada.value;

        await tester.pumpWidget(
          conApp(StatusPill(text: 'X', type: entrada.key)),
        );

        final contenedor = tester.widget<Container>(
          find.ancestor(
            of: find.text('X'),
            matching: find.byType(Container),
          ).first,
        );
        final decoracion = contenedor.decoration as BoxDecoration;
        expect(decoracion.color, fondo,
            reason: 'el fondo de ${entrada.key.name} no es el esperado');

        final texto = tester.widget<Text>(find.text('X'));
        expect(texto.style?.color, letra,
            reason: 'la letra de ${entrada.key.name} no es la esperada');
      }
    });

    testWidgets('el fondo y la letra nunca son el mismo color',
        (tester) async {
      // Si alguien copia mal una rama del switch, el pill queda ilegible.
      for (final tipo in StatusType.values) {
        await tester.pumpWidget(conApp(StatusPill(text: 'X', type: tipo)));

        final contenedor = tester.widget<Container>(
          find.ancestor(
            of: find.text('X'),
            matching: find.byType(Container),
          ).first,
        );
        final fondo = (contenedor.decoration as BoxDecoration).color;
        final letra = tester.widget<Text>(find.text('X')).style?.color;

        expect(fondo, isNot(letra), reason: '${tipo.name} queda ilegible');
      }
    });
  });

  group('AppTheme', () {
    testWidgets('el tema se aplica sin romper el árbol', (tester) async {
      await tester.pumpWidget(conApp(const Text('hola')));
      expect(find.text('hola'), findsOneWidget);

      final contexto = tester.element(find.text('hola'));
      expect(Theme.of(contexto).colorScheme.primary, isNotNull);
    });
  });
}
