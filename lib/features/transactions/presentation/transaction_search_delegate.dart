import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/transaction_list_tile.dart';
import 'transaction_detail_screen.dart';

class TransactionSearchDelegate extends SearchDelegate<Transaction?> {
  final WidgetRef ref;

  TransactionSearchDelegate(this.ref);

  @override
  String get searchFieldLabel => 'Search transactions...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResultsView(query: query, ref: ref);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchResultsView(query: query, ref: ref);
  }
}

class _SearchResultsView extends ConsumerStatefulWidget {
  final String query;
  final WidgetRef ref;

  const _SearchResultsView({required this.query, required this.ref});

  @override
  ConsumerState<_SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends ConsumerState<_SearchResultsView> {
  int? _selectedAccountId;
  String _typeFilter = 'ALL'; // 'ALL', 'EXPENSE', 'INCOME', 'TRANSFER'

  @override
  Widget build(BuildContext context) {
    final db = widget.ref.watch(databaseProvider);
    final accountsAsync = widget.ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? <Account>[];

    final accountsMap = <int, Account>{};
    for (final acc in accounts) {
      accountsMap[acc.id] = acc;
    }

    return Column(
      children: [
        // Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // All types
              ChoiceChip(
                label: const Text('All'),
                selected: _typeFilter == 'ALL',
                onSelected: (_) => setState(() => _typeFilter = 'ALL'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Expenses'),
                selected: _typeFilter == 'EXPENSE',
                onSelected: (_) => setState(() => _typeFilter = 'EXPENSE'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Income'),
                selected: _typeFilter == 'INCOME',
                onSelected: (_) => setState(() => _typeFilter = 'INCOME'),
              ),
              const SizedBox(width: 12),
              // Account selector dropdown chip
              PopupMenuButton<int?>(
                child: Chip(
                  avatar: const Icon(Icons.account_balance_wallet_outlined, size: 16),
                  label: Text(
                    _selectedAccountId != null
                        ? (accountsMap[_selectedAccountId]?.label ?? 'Account')
                        : 'All Accounts',
                  ),
                ),
                onSelected: (accId) => setState(() => _selectedAccountId = accId),
                itemBuilder: (ctx) => [
                  const PopupMenuItem<int?>(
                    value: null,
                    child: Text('All Accounts'),
                  ),
                  ...accounts.map(
                    (acc) => PopupMenuItem<int?>(
                      value: acc.id,
                      child: Text(acc.label),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Live Results Stream
        Expanded(
          child: StreamBuilder<List<Transaction>>(
            stream: db.searchTransactionsStream(
              queryText: widget.query,
              accountId: _selectedAccountId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var results = snapshot.data ?? <Transaction>[];

              // Apply type filter
              if (_typeFilter == 'EXPENSE') {
                results = results.where((t) => t.amount < 0 && t.transferPeer == null && t.transferAccount == null).toList();
              } else if (_typeFilter == 'INCOME') {
                results = results.where((t) => t.amount > 0 && t.transferPeer == null && t.transferAccount == null).toList();
              } else if (_typeFilter == 'TRANSFER') {
                results = results.where((t) => t.transferPeer != null || t.transferAccount != null).toList();
              }

              if (results.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 52,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.query.isEmpty
                            ? 'Start typing to search transactions...'
                            : 'No transactions found matching "${widget.query}"',
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final tx = results[index];
                  return TransactionListTile(
                    transaction: tx,
                    account: accountsMap[tx.accountId],
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => TransactionDetailSheet(
                          transaction: tx,
                          account: accountsMap[tx.accountId],
                          transferAccount: tx.transferAccount != null ? accountsMap[tx.transferAccount] : null,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
