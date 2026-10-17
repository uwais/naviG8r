import "package:flutter/material.dart";

import "nv_account_sheet.dart";
import "tokens.dart";

/// The top of every signed-in screen. The company, with the person and role under it, is one
/// button that opens the account menu; it replaces the organisation drop-down, refresh,
/// sign-out and avatar. A driver's task screen shows Back and the task's name instead.
class NvHeader extends StatelessWidget implements PreferredSizeWidget {
  const NvHeader({
    required String this.company,
    required String this.person,
    required String this.role,
    required String this.phone,
    required List<NvCompany> this.companies,
    required this.currentCompanyId,
    required NvSwitchCompany this.onSwitch,
    required VoidCallback this.onSignOut,
    this.onAddCompany,
    this.backLabel,
    this.onBack,
    super.key,
  }) : taskTitle = null;

  /// A driver's task screen, for example Back to "Trip" with the title "E-way bills". With no
  /// title it is the Back bar of the signed-out sign-in screens.
  const NvHeader.task({
    required String this.backLabel,
    required VoidCallback this.onBack,
    this.taskTitle,
    super.key,
  })  : company = null,
        person = null,
        role = null,
        phone = null,
        companies = null,
        currentCompanyId = null,
        onSwitch = null,
        onSignOut = null,
        onAddCompany = null;

  final String? company;
  final String? person;
  final String? role;
  final String? phone;
  final List<NvCompany>? companies;
  final String? currentCompanyId;
  final NvSwitchCompany? onSwitch;
  final VoidCallback? onSignOut;
  final VoidCallback? onAddCompany;

  /// The screen Back returns to, for example "Shipments". Null shows no Back.
  final String? backLabel;
  final VoidCallback? onBack;
  final String? taskTitle;

  static const height = 72.0;

  /// The header's height is fixed, so its text stops growing here and long names end in
  /// "..."; the account button's spoken label always carries the full words.
  static const _largestTextScale = 1.4;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  void _openAccountMenu(BuildContext context) => showNvAccountSheet(
        context: context,
        person: person!,
        phone: phone!,
        companies: companies!,
        currentCompanyId: currentCompanyId,
        onSwitch: onSwitch!,
        onSignOut: onSignOut!,
        onAddCompany: onAddCompany,
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NvColors.page,
      shape: const Border(bottom: BorderSide(color: NvColors.line)),
      child: SafeArea(
        bottom: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: _largestTextScale,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NvSpace.s2),
              child: Row(children: [
                if (backLabel != null)
                  TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.chevron_left, size: 22),
                    label: Text(backLabel!, maxLines: 1),
                    style: TextButton.styleFrom(
                        foregroundColor: NvColors.navyInk,
                        padding: const EdgeInsets.only(
                            left: NvSpace.s1, right: NvSpace.s2)),
                  ),
                if (company != null)
                  Flexible(child: _accountButton(context))
                else if (taskTitle != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: NvSpace.s2),
                      child: Semantics(
                        header: true,
                        child: Text(taskTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NvText.bodyStrong
                                .copyWith(color: NvColors.navyInk)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountButton(BuildContext context) => Semantics(
        button: true,
        label: "$company, $person, $role. Switch company or sign out",
        excludeSemantics: true,
        onTap: () => _openAccountMenu(context),
        child: InkWell(
          onTap: () => _openAccountMenu(context),
          borderRadius: BorderRadius.circular(NvRadius.button),
          highlightColor: NvColors.sunken,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NvSpace.targetMin),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: NvSpace.s2, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NvText.bodyStrong.copyWith(
                              fontWeight: FontWeight.w700,
                              color: NvColors.navyInk)),
                      Text("$person · $role",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NvText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: NvSpace.s2),
                const Icon(Icons.expand_more, color: NvColors.slate),
              ]),
            ),
          ),
        ),
      );
}
