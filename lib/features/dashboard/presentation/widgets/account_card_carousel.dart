import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/database.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/currency_formatter.dart';

import '../../../accounts/presentation/create_account_dialog.dart';

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
        if (accounts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: InkWell(
              onTap: () => CreateAccountDialog.show(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '+ Create Your First Account (e.g. Cash, Bank)',
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 13),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SizedBox(
          height: 94,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: accounts.length + 2, // +1 for "All Accounts", +1 for "+ Add Account"
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

              if (index == accounts.length + 1) {
                // "+ Add Account" card
                return _AddAccountChip(
                  onTap: () => CreateAccountDialog.show(context),
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
                onLongPress: () {
                  CreateAccountDialog.show(context, initialAccount: account);
                },
              );
            },
          ),
        );
      },
      loading: () => const SizedBox(height: 94),
      error: (err, stack) => const SizedBox.shrink(),
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
  final VoidCallback? onLongPress;

  const _AccountItemCard({
    super.key,
    required this.account,
    required this.index,
    required this.isSelected,
    required this.balance,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = AppColors.getAccountColor(account.color, index);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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

class _AddAccountChip extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            width: 1.2,
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_rounded,
              size: 22,
              color: AppColors.primary,
            ),
            SizedBox(height: 8),
            Text(
              '+ Account',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
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
