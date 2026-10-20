import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/models/models.dart';
import 'package:don_chacho_matarife/utils/formatters.dart';

TextEditingValue tecleo(String texto, {int? cursor}) => TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: cursor ?? texto.length),
    );

void main() {
  const f = MilesInputFormatter();

  test('escribe 10000000 digito por digito', () {
    var v = tecleo('', cursor: 0);
    for (final d in '10000000'.split('')) {
      final nuevo = tecleo(
        v.text.substring(0, v.selection.baseOffset) +
            d +
            v.text.substring(v.selection.baseOffset),
        cursor: v.selection.baseOffset + 1,
      );
      v = f.formatEditUpdate(v, nuevo);
    }
    expect(v.text, '10.000.000');
    expect(v.selection.baseOffset, 10);
    expect(parseNumero(v.text), 10000000);
  });

  test('decimales con coma', () {
    final v = f.formatEditUpdate(const TextEditingValue(), tecleo('1234,56'));
    expect(v.text, '1.234,56');
    expect(parseNumero(v.text), 1234.56);
  });

  test('cursor en el medio', () {
    // "1.234" y escribo un 9 justo despues del 1 -> "12.349"? no: "1934"->"1.934"
    final v = f.formatEditUpdate(tecleo('1.234'), tecleo('19.234', cursor: 2));
    expect(v.text, '19.234');
    expect(v.selection.baseOffset, 2);
  });

  test('borrar todo deja vacio', () {
    final v = f.formatEditUpdate(tecleo('1.000'), tecleo(''));
    expect(v.text, '');
  });

  test('ceros a la izquierda', () {
    final v = f.formatEditUpdate(const TextEditingValue(), tecleo('007'));
    expect(v.text, '7');
  });

  test('cero coma cinco', () {
    final v = f.formatEditUpdate(const TextEditingValue(), tecleo('0,5'));
    expect(v.text, '0,5');
    expect(parseNumero(v.text), 0.5);
  });

  test('max decimales', () {
    const dos = MilesInputFormatter(decimales: 2);
    final v = dos.formatEditUpdate(const TextEditingValue(), tecleo('5,999'));
    expect(v.text, '5,99');
  });

  test('textoMiles ida y vuelta', () {
    expect(textoMiles(10000000), '10.000.000');
    expect(textoMiles(1234.5), '1.234,5');
    expect(textoMiles(0), '');
    expect(parseNumero(textoMiles(72050773)), 72050773);
  });

  group('redondearKg - de 0,6 para arriba sube; de 0,5 para abajo baja', () {
    test('sube arriba de 0,5', () {
      expect(redondearKg(5403.657), 5404);
      expect(redondearKg(5403.6), 5404);
      expect(redondearKg(28.51), 29);
    });

    test('baja en 0,5 y abajo', () {
      expect(redondearKg(5403.5), 5403);
      expect(redondearKg(5403.4), 5403);
      expect(redondearKg(28.5), 28);
    });

    test('enteros quedan igual', () {
      expect(redondearKg(5375), 5375);
      expect(redondearKg(0), 0);
    });

    test('negativos redondean por valor absoluto', () {
      expect(redondearKg(-28.657), -29);
      expect(redondearKg(-28.5), -28);
    });
  });

  test('el bloque de rinde cierra: esperados - obtenidos = diferencia', () {
    // 9.316 kg netos al 58% = 5.403,28 -> 5.403 esperados
    final carga = Carga(
      fecha: DateTime(2026, 10, 20),
      proveedorId: 'p1',
      cantidadAnimales: 35,
      kgVivo: 9806.32,
      desvastePorcentaje: 5,
      precioKgVivo: 5400,
      rindeAsegurado: 58,
      kgMediaRes: 5375,
    );
    expect(carga.kgEsperados, carga.kgEsperados.roundToDouble());
    expect(carga.diferenciaRindeKg, carga.kgEsperados - 5375);
    expect(carga.diferenciaRindePesos, carga.diferenciaRindeKg! * 5400);
  });
}
