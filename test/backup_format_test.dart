import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hannahswalletapp/core/constants/app_constants.dart';
import 'package:hannahswalletapp/core/error/failures.dart';
import 'package:hannahswalletapp/data/datasources/local/data_change_bus.dart';
import 'package:hannahswalletapp/data/datasources/local/database_provider.dart';
import 'package:hannahswalletapp/data/security/encryption_key_manager.dart';
import 'package:hannahswalletapp/data/services/backup_service.dart';

/// Pruebas de validacion del formato de copia de seguridad.
///
/// `inspect` es la barrera que se cruza ANTES de tocar la base: se ejecuta
/// sobre el JSON en memoria y no abre SQLCipher, asi que se puede probar sin
/// dispositivo. Ahi esta justamente su valor: rechazar un fichero ajeno o
/// truncado antes de haber borrado nada.
void main() {
  late BackupService service;

  setUp(() {
    service = BackupService(
      DatabaseProvider(EncryptionKeyManager()),
      DataChangeBus(),
    );
  });

  String buildBackup({
    Map<String, dynamic>? data,
    int formatVersion = AppConstants.backupFormatVersion,
    String magic = AppConstants.backupMagic,
    String? checksum,
  }) {
    final Map<String, dynamic> payload = data ??
        <String, dynamic>{
          'wallets': <dynamic>[<String, dynamic>{'id': 'w1', 'name': 'Efectivo'}],
          'categories': <dynamic>[],
          'recurring_rules': <dynamic>[],
          'transactions': <dynamic>[
            <String, dynamic>{'id': 't1'},
            <String, dynamic>{'id': 't2'},
          ],
          'budgets': <dynamic>[],
          'app_settings': <dynamic>[],
        };

    return jsonEncode(<String, dynamic>{
      'magic': magic,
      'format_version': formatVersion,
      'schema_version': 1,
      'exported_at': '2026-08-20T10:00:00.000Z',
      'checksum': ?checksum,
      'data': payload,
    });
  }

  group('inspect: ficheros validos', () {
    test('cuenta las filas de cada tabla', () async {
      final BackupPreview preview = await service.inspect(buildBackup());
      expect(preview.transactionCount, 2);
      expect(preview.walletCount, 1);
      expect(preview.categoryCount, 0);
      expect(preview.budgetCount, 0);
    });

    test('lee la fecha de exportacion', () async {
      final BackupPreview preview = await service.inspect(buildBackup());
      expect(preview.exportedAt, isNotNull);
      expect(preview.exportedAt!.year, 2026);
    });

    test('marca el checksum como incorrecto si no cuadra', () async {
      final BackupPreview preview =
          await service.inspect(buildBackup(checksum: 'deadbeef'));
      // No es motivo de rechazo -editar el JSON a mano es un uso legitimo de
      // un formato abierto-, pero la UI avisa.
      expect(preview.checksumOk, isFalse);
    });

    test('sin checksum tampoco falla', () async {
      final BackupPreview preview = await service.inspect(buildBackup());
      expect(preview.checksumOk, isFalse);
    });
  });

  group('inspect: ficheros rechazados', () {
    test('rechaza un JSON invalido', () {
      expect(
        () => service.inspect('esto no es json {{{'),
        throwsA(isA<BackupFormatFailure>()),
      );
    });

    test('rechaza un JSON que no es un objeto', () {
      expect(
        () => service.inspect('[1, 2, 3]'),
        throwsA(isA<BackupFormatFailure>()),
      );
    });

    test('rechaza un fichero de otra aplicacion', () {
      expect(
        () => service.inspect(buildBackup(magic: 'otra_app_backup')),
        throwsA(isA<BackupFormatFailure>()),
      );
    });

    test('rechaza un formato mas nuevo que el que entiende esta version', () {
      // Restaurar un backup del futuro podria perder campos en silencio.
      expect(
        () => service.inspect(buildBackup(formatVersion: 99)),
        throwsA(isA<BackupFormatFailure>()),
      );
    });

    test('rechaza un fichero sin seccion de datos', () {
      final String json = jsonEncode(<String, dynamic>{
        'magic': AppConstants.backupMagic,
        'format_version': AppConstants.backupFormatVersion,
      });
      expect(
        () => service.inspect(json),
        throwsA(isA<BackupFormatFailure>()),
      );
    });

    test('acepta un formato mas antiguo', () async {
      // Hacia atras SI se admite: es lo que permite restaurar una copia vieja
      // despues de actualizar la app.
      final BackupPreview preview =
          await service.inspect(buildBackup());
      expect(preview.formatVersion, 1);
    });
  });

  group('tolerancia de campos', () {
    test('las tablas que falten cuentan como vacias', () async {
      final BackupPreview preview = await service.inspect(
        buildBackup(data: <String, dynamic>{'wallets': <dynamic>[]}),
      );
      expect(preview.transactionCount, 0);
      expect(preview.categoryCount, 0);
    });
  });
}
