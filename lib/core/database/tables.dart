import 'package:drift/drift.dart';

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  IntColumn get openingBalance => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('INR'))();
  IntColumn get color => integer().withDefault(const Constant(-16738680))();
  TextColumn get grouping => text().withDefault(const Constant('MONTH'))();
  TextColumn get balanceType => text().withDefault(const Constant('CURRENT'))();
  TextColumn get uuid => text().nullable()();
  BoolColumn get excludeFromTotals => boolean().withDefault(const Constant(false))();
  BoolColumn get sealed => boolean().withDefault(const Constant(false))();
  IntColumn get sortKey => integer().withDefault(const Constant(0))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  IntColumn get parentId => integer().nullable().references(Categories, #id)();
  IntColumn get color => integer().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get type => integer().withDefault(const Constant(0))();
  TextColumn get uuid => text().nullable()();
}

class Payees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get shortName => text().nullable()();
  TextColumn get iban => text().nullable()();
  TextColumn get bic => text().nullable()();
}

class PaymentMethods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  IntColumn get type => integer().withDefault(const Constant(0))();
  TextColumn get icon => text().nullable()();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get comment => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get valueDate => dateTime()();
  IntColumn get amount => integer()(); // Stored in cents/paise (e.g. -14500 is -₹145.00)
  IntColumn get catId => integer().nullable().references(Categories, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get payeeId => integer().nullable().references(Payees, #id)();
  IntColumn get transferPeer => integer().nullable().references(Transactions, #id)();
  IntColumn get transferAccount => integer().nullable().references(Accounts, #id)();
  IntColumn get methodId => integer().nullable().references(PaymentMethods, #id)();
  IntColumn get parentId => integer().nullable().references(Transactions, #id)();
  IntColumn get status => integer().withDefault(const Constant(0))();
  TextColumn get crStatus => text().withDefault(const Constant('RECONCILED'))();
  TextColumn get number => text().nullable()();
  TextColumn get uuid => text().nullable()();
  IntColumn get debtId => integer().nullable()();
}

class Currencies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  TextColumn get symbol => text().nullable()();
  IntColumn get fractionDigits => integer().withDefault(const Constant(2))();
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
