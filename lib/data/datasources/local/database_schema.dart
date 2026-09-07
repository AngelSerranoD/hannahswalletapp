/// Definicion declarativa del esquema SQLite.
///
/// Vive separado de [DatabaseProvider] para que el esquema se lea de un
/// vistazo y para que los tests puedan montarlo sobre una base en memoria.
///
/// Convenciones que se respetan en TODAS las tablas:
///
///  * `id` es TEXT (UUID v4). Evita colisiones al fusionar backups de dos
///    dispositivos, cosa que un autoincremental entero haría imposible.
///  * Las fechas son INTEGER: milisegundos desde epoch en UTC.
///  * El dinero es INTEGER en centimos. Jamas REAL (ver `core/utils/money.dart`).
///  * Los booleanos son INTEGER 0/1, que es lo que SQLite entiende.
///  * `is_deleted` implementa borrado lógico: nada se borra fisicamente, de
///    modo que un movimiento antiguo nunca deja huerfano a un informe ya
///    calculado y el usuario puede recuperar categorías por error.
abstract final class DatabaseSchema {
  static const String tableWallets = 'wallets';
  static const String tableCategories = 'categories';

  /// OJO: `transactions` es palabra reservada de SQL. Hay que entrecomillarla
  /// con comillas dobles en cada sentencia o SQLite dara un error de sintaxis.
  static const String tableTransactions = '"transactions"';
  static const String tableBudgets = 'budgets';
  static const String tableRecurringRules = 'recurring_rules';
  static const String tableSettings = 'app_settings';

  /// Sentencias del `onCreate`, en orden de dependencia.
  static const List<String> createStatements = <String>[
    '''
    CREATE TABLE wallets (
      id                    TEXT    PRIMARY KEY,
      name                  TEXT    NOT NULL,
      icon_code             INTEGER NOT NULL,
      color_value           INTEGER NOT NULL,
      currency_code         TEXT    NOT NULL DEFAULT 'EUR',
      initial_balance_cents INTEGER NOT NULL DEFAULT 0,
      is_default            INTEGER NOT NULL DEFAULT 0,
      is_archived           INTEGER NOT NULL DEFAULT 0,
      sort_order            INTEGER NOT NULL DEFAULT 0,
      created_at            INTEGER NOT NULL,
      updated_at            INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE categories (
      id          TEXT    PRIMARY KEY,
      name        TEXT    NOT NULL,
      icon_code   INTEGER NOT NULL,
      color_value INTEGER NOT NULL,
      type        TEXT    NOT NULL CHECK (type IN ('expense', 'income')),
      is_deleted  INTEGER NOT NULL DEFAULT 0,
      is_system   INTEGER NOT NULL DEFAULT 0,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL,
      updated_at  INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE recurring_rules (
      id             TEXT    PRIMARY KEY,
      wallet_id      TEXT    NOT NULL REFERENCES wallets (id) ON DELETE CASCADE,
      category_id    TEXT    REFERENCES categories (id) ON DELETE SET NULL,
      type           TEXT    NOT NULL CHECK (type IN ('expense', 'income')),
      amount_cents   INTEGER NOT NULL CHECK (amount_cents > 0),
      note           TEXT,
      frequency      TEXT    NOT NULL
                             CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
      interval_count INTEGER NOT NULL DEFAULT 1 CHECK (interval_count > 0),
      next_run_at    INTEGER NOT NULL,
      end_at         INTEGER,
      last_run_at    INTEGER,
      is_active      INTEGER NOT NULL DEFAULT 1,
      is_deleted     INTEGER NOT NULL DEFAULT 0,
      created_at     INTEGER NOT NULL,
      updated_at     INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE "transactions" (
      id                 TEXT    PRIMARY KEY,
      wallet_id          TEXT    NOT NULL REFERENCES wallets (id) ON DELETE CASCADE,
      category_id        TEXT    REFERENCES categories (id) ON DELETE SET NULL,
      type               TEXT    NOT NULL
                                 CHECK (type IN ('expense', 'income', 'transfer')),
      amount_cents       INTEGER NOT NULL CHECK (amount_cents > 0),
      note               TEXT,
      occurred_at        INTEGER NOT NULL,
      transfer_wallet_id TEXT    REFERENCES wallets (id) ON DELETE SET NULL,
      recurring_rule_id  TEXT    REFERENCES recurring_rules (id) ON DELETE SET NULL,
      is_deleted         INTEGER NOT NULL DEFAULT 0,
      created_at         INTEGER NOT NULL,
      updated_at         INTEGER NOT NULL,
      CHECK (type <> 'transfer' OR transfer_wallet_id IS NOT NULL),
      CHECK (transfer_wallet_id IS NULL OR transfer_wallet_id <> wallet_id)
    )
    ''',
    '''
    CREATE TABLE budgets (
      id           TEXT    PRIMARY KEY,
      category_id  TEXT    REFERENCES categories (id) ON DELETE CASCADE,
      month_key    TEXT,
      limit_cents  INTEGER NOT NULL CHECK (limit_cents > 0),
      is_deleted   INTEGER NOT NULL DEFAULT 0,
      created_at   INTEGER NOT NULL,
      updated_at   INTEGER NOT NULL
    )
    ''',
    '''
    CREATE TABLE app_settings (
      key        TEXT PRIMARY KEY,
      value      TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
    ''',
  ];

  /// Indices. Cada uno responde a una consulta real de la app.
  static const List<String> indexStatements = <String>[
    // El dashboard y las estadísticas filtran por rango de fecha y ordenan
    // descendente: este índice convierte ese barrido en una lectura de rango.
    'CREATE INDEX idx_tx_occurred_at ON "transactions" (occurred_at DESC)',
    'CREATE INDEX idx_tx_wallet ON "transactions" (wallet_id, occurred_at DESC)',
    'CREATE INDEX idx_tx_category ON "transactions" (category_id, occurred_at DESC)',
    'CREATE INDEX idx_tx_live ON "transactions" (is_deleted, occurred_at DESC)',
    'CREATE INDEX idx_tx_transfer_wallet ON "transactions" (transfer_wallet_id)',
    'CREATE INDEX idx_categories_live ON categories (is_deleted, type, sort_order)',
    'CREATE INDEX idx_budgets_month ON budgets (month_key, is_deleted)',
    'CREATE INDEX idx_recurring_due ON recurring_rules (is_active, is_deleted, next_run_at)',

    // Unicidad lógica de presupuestos: como máximo un presupuesto vivo por
    // (categoría, mes). El índice es PARCIAL (`WHERE is_deleted = 0`) para que
    // los presupuestos borrados no bloqueen la creacion de uno nuevo igual.
    // `COALESCE` mapea los NULL (presupuesto global / plantilla mensual) a un
    // centinela, porque en SQL dos NULL no son iguales entre si y el índice
    // único dejaria colar duplicados.
    '''
    CREATE UNIQUE INDEX idx_budget_unique
      ON budgets (COALESCE(category_id, '@global'), COALESCE(month_key, '@every'))
      WHERE is_deleted = 0
    ''',
  ];

  /// Saldo acumulado histórico de TODAS las carteras activas.
  ///
  /// Este es el nucleo del "problema de los reinicios mensuales": la cabecera
  /// no debe mostrar el neto del mes en curso (que cada día 1 volvería a cero
  /// y daría la falsa sensacion de estar arruinado), sino el patrimonio real
  /// acumulado desde el principio de los tiempos.
  ///
  /// Por eso la consulta:
  ///   * NO lleva filtro por fecha: recorre el histórico completo.
  ///   * Parte del `initial_balance_cents` de cada cartera, que es lo que ya
  ///     habia antes de empezar a usar la app.
  ///   * Ignora las transferencias (`ELSE 0`): mover 50 EUR del banco al
  ///     efectivo no crea ni destruye patrimonio, solo lo recoloca. Sumarlas
  ///     inflaría el total.
  ///   * Excluye borrados logicos y carteras archivadas.
  static const String queryLifetimeBalance = '''
    SELECT
      (
        SELECT COALESCE(SUM(initial_balance_cents), 0)
        FROM wallets
        WHERE is_archived = 0
      )
      +
      COALESCE((
        SELECT SUM(
          CASE t.type
            WHEN 'income'  THEN  t.amount_cents
            WHEN 'expense' THEN -t.amount_cents
            ELSE 0
          END
        )
        FROM "transactions" t
        JOIN wallets w ON w.id = t.wallet_id
        WHERE t.is_deleted = 0 AND w.is_archived = 0
      ), 0) AS balance_cents
  ''';

  /// Saldo por cartera. Suma los movimientos propios y, además, las
  /// transferencias ENTRANTES (donde esta cartera es el destino).
  static const String queryWalletBalances = '''
    SELECT
      w.id AS wallet_id,
      w.initial_balance_cents
      + COALESCE((
          SELECT SUM(
            CASE t.type
              WHEN 'income'   THEN  t.amount_cents
              WHEN 'expense'  THEN -t.amount_cents
              WHEN 'transfer' THEN -t.amount_cents
            END
          )
          FROM "transactions" t
          WHERE t.wallet_id = w.id AND t.is_deleted = 0
        ), 0)
      + COALESCE((
          SELECT SUM(t.amount_cents)
          FROM "transactions" t
          WHERE t.transfer_wallet_id = w.id
            AND t.type = 'transfer'
            AND t.is_deleted = 0
        ), 0) AS balance_cents
    FROM wallets w
    WHERE w.is_archived = 0
    ORDER BY w.sort_order ASC, w.created_at ASC
  ''';

  /// Ingresos y gastos de un intervalo `[start, end)`.
  ///
  /// Las transferencias quedan fuera a proposito: no son ni ingreso ni gasto.
  static const String queryPeriodTotals = '''
    SELECT
      COALESCE(SUM(CASE WHEN t.type = 'income'  THEN t.amount_cents END), 0) AS income_cents,
      COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_cents END), 0) AS expense_cents
    FROM "transactions" t
    JOIN wallets w ON w.id = t.wallet_id
    WHERE t.is_deleted = 0
      AND w.is_archived = 0
      AND t.occurred_at >= ?
      AND t.occurred_at <  ?
  ''';

  /// Gasto agrupado por categoría en un intervalo. Alimenta el donut y la
  /// barra de progreso de cada presupuesto.
  static const String queryExpenseByCategory = '''
    SELECT
      c.id          AS category_id,
      c.name        AS category_name,
      c.icon_code   AS icon_code,
      c.color_value AS color_value,
      SUM(t.amount_cents) AS total_cents,
      COUNT(t.id)         AS entry_count
    FROM "transactions" t
    JOIN wallets w    ON w.id = t.wallet_id
    LEFT JOIN categories c ON c.id = t.category_id
    WHERE t.is_deleted = 0
      AND w.is_archived = 0
      AND t.type = 'expense'
      AND t.occurred_at >= ?
      AND t.occurred_at <  ?
    GROUP BY c.id
    ORDER BY total_cents DESC
  ''';
}
