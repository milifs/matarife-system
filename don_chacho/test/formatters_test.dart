import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
