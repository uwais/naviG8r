import "package:flutter/material.dart";

import "nv_button.dart";
import "nv_sheet.dart";
import "tokens.dart";

/// One company the person belongs to, as the account menu lists it.
class NvCompany {
  const NvCompany({required this.id, required this.name, this.role});
  final String id;
  final String name;

  /// The person's role there, for example "Carrier · Dispatcher". Left out when not known.
  final String? role;
}

/// Switches to the company with this id. Returns null when it worked, or the words saying
/// why it did not, which the sheet shows while it stays open.
typedef NvSwitchCompany = Future<String?> Function(String companyId);

/// Opens the account menu: the only place to switch company or sign out.
Future<void> showNvAccountSheet({
  required BuildContext context,
  required String person,
  required String phone,
  required List<NvCompany> companies,
  required String? currentCompanyId,
  required NvSwitchCompany onSwitch,
  required VoidCallback onSignOut,
  VoidCallback? onAddCompany,
}) {
  return showNvSheet<void>(
    context: context,
    builder: (_) => NvAccountSheet(
      person: person,
      phone: phone,
      companies: companies,
      currentCompanyId: currentCompanyId,
      onSwitch: onSwitch,
      onSignOut: onSignOut,
      onAddCompany: onAddCompany,
    ),
  );
}

class NvAccountSheet extends StatefulWidget {
  const NvAccountSheet(
      {required this.person,
      required this.phone,
      required this.companies,
      required this.currentCompanyId,
      required this.onSwitch,
      required this.onSignOut,
      this.onAddCompany,
      super.key});
  final String person;

  /// The full number as it should read, for example "+91 98450 12345".
  final String phone;
  final List<NvCompany> companies;
  final String? currentCompanyId;
  final NvSwitchCompany onSwitch;
  final VoidCallback onSignOut;

  /// Null hides "Add a company".
  final VoidCallback? onAddCompany;

  @override
  State<NvAccountSheet> createState() => _NvAccountSheetState();
}

class _NvAccountSheetState extends State<NvAccountSheet> {
  String? _switchingToId;
  String? _switchError;

  Future<void> _switchTo(String companyId) async {
    if (_switchingToId != null || companyId == widget.currentCompanyId) return;
    setState(() {
      _switchingToId = companyId;
      _switchError = null;
    });
    final error = await widget.onSwitch(companyId);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _switchingToId = null;
      _switchError = error;
    });
  }

  void _close(VoidCallback then) {
    Navigator.of(context).pop();
    then();
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = _switchingToId ?? widget.currentCompanyId;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          NvSpace.gutter, 0, NvSpace.gutter, NvSpace.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            namesRoute: true,
            child: Text(widget.person, style: NvText.heading),
          ),
          Text(widget.phone, style: NvText.caption),
          const SizedBox(height: NvSpace.s5),
          Semantics(
            header: true,
            label: "Your companies",
            excludeSemantics: true,
            child: const Text("YOUR COMPANIES", style: NvText.label),
          ),
          if (_switchError != null) ...[
            const SizedBox(height: NvSpace.s2),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(NvSpace.s3),
                decoration: BoxDecoration(
                    color: NvColors.problemTint,
                    borderRadius: BorderRadius.circular(NvRadius.button)),
                child: Text(_switchError!, style: NvText.body),
              ),
            ),
          ],
          for (final company in widget.companies) ...[
            const SizedBox(height: NvSpace.s2),
            _CompanyRow(
              company: company,
              selected: company.id == selectedId,
              switching: company.id == _switchingToId,
              showSpinner: !reduceMotion,
              onChoose:
                  _switchingToId == null ? () => _switchTo(company.id) : null,
            ),
          ],
          const SizedBox(height: NvSpace.s4),
          Container(
            decoration: BoxDecoration(
                color: NvColors.card,
                borderRadius: BorderRadius.circular(NvRadius.card),
                border: Border.all(color: NvColors.line)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              if (widget.onAddCompany != null) ...[
                ListTile(
                  minVerticalPadding: NvSpace.s3,
                  leading: const ExcludeSemantics(
                      child: Icon(Icons.add, color: NvColors.slate)),
                  title: Text("Add a company",
                      style: NvText.body.copyWith(fontSize: 16)),
                  subtitle: const Text("Register as a carrier, or join one",
                      style: NvText.caption),
                  onTap: () => _close(widget.onAddCompany!),
                ),
                const Divider(),
              ],
              ListTile(
                minVerticalPadding: NvSpace.s3,
                leading: const ExcludeSemantics(
                    child: Icon(Icons.logout, color: NvColors.slate)),
                title:
                    Text("Sign out", style: NvText.body.copyWith(fontSize: 16)),
                onTap: () => _close(widget.onSignOut),
              ),
            ]),
          ),
          const SizedBox(height: NvSpace.s4),
          NvButton(
            label: "Close",
            onPressed: () => Navigator.of(context).pop(),
            kind: NvButtonKind.secondary,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}

class _CompanyRow extends StatelessWidget {
  const _CompanyRow(
      {required this.company,
      required this.selected,
      required this.switching,
      required this.showSpinner,
      required this.onChoose});
  final NvCompany company;
  final bool selected;
  final bool switching;
  final bool showSpinner;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NvRadius.button),
      side: BorderSide(
          color: selected ? NvColors.navy : NvColors.controlBorder,
          width: selected ? 2 : 1),
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: onChoose != null,
      onTap: onChoose,
      label: [company.name, if (company.role != null) company.role].join(", "),
      excludeSemantics: true,
      child: Material(
        color: selected ? NvColors.infoTint : NvColors.card,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onChoose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: NvSpace.s3, vertical: NvSpace.s2),
              child: Row(children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: switching && showSpinner
                      ? const Padding(
                          padding: EdgeInsets.all(3),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: NvColors.navy))
                      : Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? NvColors.navy
                              : NvColors.controlBorder),
                ),
                const SizedBox(width: NvSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(company.name,
                          style: NvText.body.copyWith(fontSize: 16)),
                      if (company.role != null)
                        Text(company.role!, style: NvText.caption),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
