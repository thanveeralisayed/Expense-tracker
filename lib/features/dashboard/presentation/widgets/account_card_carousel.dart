import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';

class AccountCardCarousel extends ConsumerWidget {
  const AccountCardCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final selectedAccountId = ref.watch(selectedAccountIdProvider);
    final balancesAsync = ref.watch(accountBalancesProvider);
    final balancesMap = balancesAsync.value ?? <int, int>{};

    return accountsAsync.when(
      data: (accounts) {
        if (accounts.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 94,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: accounts.length + 1, // +1 for "All Accounts"
            separatorBuilder: (context, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                // "All Accounts" card
                final isSelected = selectedAccountId == null;
                return _AllAccountsChip(
                  isSelected: isSelected,
                  onTap: () => ref.read(selectedAccountIdProvider.notifier).state = null,
                );
              }

              final account = accounts[index - 1];
              final isSelected = selectedAccountId == account.id;
              final balance = balancesMap[account.id] ?? 0;

              return _AccountItemCard(
                key: ValueKey('account_card_${account.label}'),
                account: account,
                index: index - 1,
                isSelected: isSelected,
                balance: balance,
                onTap: () {
                  ref.read(selectedAccountIdProvider.notifier).state =
                      isSelected ? null : account.id;
                },
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 94),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _AllAccountsChip extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _AllAccountsChip({
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 110,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryLight
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_rounded,
              size: 22,
              color: isSelected ? Colors.white : AppColors.primaryLight,
            ),
            const SizedBox(height: 8),
            Text(
              'All Accounts',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountItemCard extends StatelessWidget {
  final Account account;
  final int index;
  final bool isSelected;
  final int balance;
  final VoidCallback onTap;

  const _AccountItemCard({
    super.key,
    required this.account,
    required this.index,
    required this.isSelected,
    required this.balance,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppColors.getAccountColor(account.color, index);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(isDark ? 0.25 : 0.15)
              : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    account.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.formatPaise(balance),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: balance < 0
                    ? AppColors.expense
                    : (balance > 0 ? AppColors.income : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
