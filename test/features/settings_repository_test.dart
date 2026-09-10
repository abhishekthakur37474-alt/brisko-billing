import 'package:brisko_billing/core/data/local/sqlite/sqlite_database.dart';
import 'package:brisko_billing/features/settings/data/repositories/sqlite_settings_repository.dart';
import 'package:brisko_billing/features/settings/domain/models/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(TestDatabase.register);

  late SqliteDatabase database;
  late SqliteSettingsRepository settings;

  setUp(() async {
    database = await TestDatabase.openInMemory();
    settings = SqliteSettingsRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('the table starts empty; nothing is pre-populated', () async {
    // Outlet details are the owner's to enter. Inventing a business name or GSTIN
    // would put fabricated data on a tax invoice.
    expect((await settings.readAll()).valueOrNull, isEmpty);
  });

  test('a missing key reads as null rather than failing', () async {
    final result = await settings.readString(SettingKeys.businessName);
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isNull);
  });

  test('strings round-trip', () async {
    expect(
      (await settings.writeString(SettingKeys.receiptFooter, 'Thank you')).isOk,
      isTrue,
    );
    expect(
      (await settings.readString(SettingKeys.receiptFooter)).valueOrNull,
      'Thank you',
    );
  });

  test('integers round-trip, which is how the tax rate is stored', () async {
    // 5% expressed in basis points. An integer, never a double.
    await settings.writeInt(SettingKeys.gstRateBasisPoints, 500);
    expect(
      (await settings.readInt(SettingKeys.gstRateBasisPoints)).valueOrNull,
      500,
    );
  });

  test('a corrupt integer reads as null rather than crashing', () async {
    await settings.writeString(SettingKeys.gstRateBasisPoints, 'not a number');
    final result = await settings.readInt(SettingKeys.gstRateBasisPoints);
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isNull);
  });

  test('booleans round-trip and honour the supplied default', () async {
    expect(
      (await settings.readBool(SettingKeys.pricesIncludeTax)).valueOrNull,
      isFalse,
    );
    expect(
      (await settings.readBool(
        SettingKeys.pricesIncludeTax,
        defaultValue: true,
      )).valueOrNull,
      isTrue,
    );

    await settings.writeBool(SettingKeys.pricesIncludeTax, true);
    expect(
      (await settings.readBool(SettingKeys.pricesIncludeTax)).valueOrNull,
      isTrue,
    );
  });

  test('writing the same key twice updates rather than duplicating', () async {
    await settings.writeString(SettingKeys.businessPhone, '0000000000');
    await settings.writeString(SettingKeys.businessPhone, '9999999999');

    final Map<String, String?> all = (await settings.readAll()).valueOrNull!;
    expect(all, hasLength(1));
    expect(all[SettingKeys.businessPhone], '9999999999');
  });

  test('a key can be removed', () async {
    await settings.writeString(SettingKeys.upiVpa, 'test@upi');
    expect((await settings.remove(SettingKeys.upiVpa)).isOk, isTrue);
    expect((await settings.readString(SettingKeys.upiVpa)).valueOrNull, isNull);
  });
}
