
import 'package:flutter/material.dart';

import '../../../widgets/common.dart';
import '../../categories/categories_screen.dart';
import '../../recurring/recurring_screen.dart';
import '../../wallets/wallets_screen.dart';

/// Accesos a carteras, categorías y movimientos recurrentes.
class ManagementSection extends StatelessWidget {
  const ManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Carteras'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WalletsScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categorías'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CategoriesScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.autorenew_rounded),
            title: const Text('Movimientos recurrentes'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RecurringScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
