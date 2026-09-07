import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/utils/money.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pruebas del parseo de importes.
///
/// Es la funcion mas expuesta de la app: recibe lo que teclea el usuario con
/// el separador que le dé el teclado del movil. Un fallo aqui no da error,
/// simplemente guarda una cantidad equivocada, y eso no se detecta hasta que
/// el saldo no cuadra semanas despues.
void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));

  group('Money.parseToCents', () {
    test('acepta la coma decimal espanola', () {
      expect(Money.parseToCents('12,50'), 1250);
      expect(Money.parseToCents('0,99'), 99);
    });

    test('acepta el punto decimal', () {
      expect(Money.parseToCents('12.50'), 1250);
      expect(Money.parseToCents('3.5'), 350);
    });

    test('distingue millares de decimales por el ultimo separador', () {
      // Formato espanol: punto de millares, coma decimal.
      expect(Money.parseToCents('1.234,56'), 123456);
      // Formato ingles: coma de millares, punto decimal.
      expect(Money.parseToCents('1,234.56'), 123456);
    });

    test('con solo coma, la coma es siempre el decimal (es_ES)', () {
      // El teclado numerico espanol produce coma, asi que quien escribe
      // "1,234" esta poniendo decimales, no millares. Se redondea al centimo.
      expect(Money.parseToCents('1,234'), 123);
      expect(Money.parseToCents('1,2'), 120);
    });

    test('con solo punto y tres cifras detras, el punto es de millares', () {
      // "1.234" en espanol son mil doscientos treinta y cuatro euros.
      expect(Money.parseToCents('1.234'), 123400);
      expect(Money.parseToCents('12.500'), 1250000);
    });

    test('con solo punto y una o dos cifras detras, el punto es decimal', () {
      expect(Money.parseToCents('12.5'), 1250);
      expect(Money.parseToCents('12.50'), 1250);
    });

    test('encadena varios puntos de millares', () {
      expect(Money.parseToCents('1.234.567'), 123456700);
    });

    test('ignora simbolos y espacios', () {
      expect(Money.parseToCents(' 45,00 EUR '), 4500);
      expect(Money.parseToCents('12,30 €'), 1230);
    });

    test('admite enteros sin decimales', () {
      expect(Money.parseToCents('40'), 4000);
    });

    test('conserva el signo negativo', () {
      expect(Money.parseToCents('-25,10'), -2510);
    });

    test('devuelve null cuando no hay numero', () {
      expect(Money.parseToCents(''), isNull);
      expect(Money.parseToCents('   '), isNull);
      expect(Money.parseToCents('abc'), isNull);
      expect(Money.parseToCents('-'), isNull);
    });

    test('redondea al centimo mas cercano', () {
      expect(Money.parseToCents('1,005'), 100);
      expect(Money.parseToCents('1,006'), 101);
    });

    test('la suma en centimos no acumula error de coma flotante', () {
      // El motivo de guardar el dinero en enteros: 0,1 + 0,2 en double da
      // 0.30000000000000004, y tras cientos de movimientos el saldo se
      // desviaria. En centimos la suma es exacta.
      final int a = Money.parseToCents('0,10')!;
      final int b = Money.parseToCents('0,20')!;
      expect(a + b, 30);
    });
  });

  group('Money.format', () {
    test('anade el simbolo de la moneda', () {
      expect(Money.format(1250), contains('€'));
      expect(Money.format(1250, currencyCode: 'GBP'), contains('£'));
    });

    test('marca los negativos con el signo delante', () {
      expect(Money.format(-500).startsWith('-'), isTrue);
    });

    test('con showSign marca tambien los positivos', () {
      expect(Money.format(500, showSign: true).startsWith('+'), isTrue);
    });
  });

  group('Money.centsToPlainString', () {
    test('devuelve dos decimales sin simbolo', () {
      expect(Money.centsToPlainString(1250), '12,50');
      expect(Money.centsToPlainString(5), '0,05');
    });

    test('es reversible con parseToCents', () {
      for (final int cents in <int>[0, 5, 99, 1250, 123456, 999999]) {
        expect(Money.parseToCents(Money.centsToPlainString(cents)), cents);
      }
    });
  });
}
