import 'package:flutter/material.dart';

import 'authorization_session.dart';
import 'pilot_api.dart';

/// Kept outside the route navigator so organization selection is always available.
class OrganizationAccess extends StatelessWidget {
  const OrganizationAccess({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthorizationSession.revision,
      builder: (context, _) {
        if (!AuthorizationSession.initialized ||
            AuthorizationSession.switching) {
          return const Material(
              child: Center(child: CircularProgressIndicator()));
        }
        final signedIn = AuthorizationSession.signedIn;
        final org = AuthorizationSession.organization;
        final internal = org?['kind'] == 'PLATFORM';
        final blocked = signedIn &&
            (AuthorizationSession.principal == null ||
                (!AuthorizationSession.hasRole('SHIPPER') &&
                    !AuthorizationSession.hasRole('CARRIER')));
        return Material(
          child: Column(
            children: [
              if (signedIn && (blocked || AuthorizationSession.error != null))
                const OrganizationToolbar(),
              Expanded(
                child: blocked || AuthorizationSession.error != null
                    ? Center(
                        child: SingleChildScrollView(
                            child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              internal
                                  ? 'Internal workspace'
                                  : 'Company access',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Text(AuthorizationSession.error ??
                              (internal
                                  ? 'Use the operations portal for Finance, Operations, and Admin work. Choose a shipper or carrier company above to use it in the app.'
                                  : AuthorizationSession.organizations.isEmpty
                                      ? 'You are not a member of any company yet. Contact your company admin.'
                                      : AuthorizationSession.principal == null
                                          ? 'Choose a company above to continue.'
                                          : 'You cannot use the app for this company. Contact your company admin.')),
                          if (internal) ...[
                            const SizedBox(height: 12),
                            SelectableText(
                                '${api.baseUrl.replaceFirst(RegExp(r"/api/?$"), "")}/ops'),
                          ],
                          if (AuthorizationSession.error != null)
                            const TextButton(
                                onPressed: AuthorizationSession.refresh,
                                child: Text('Try again')),
                        ]),
                      )))
                    : KeyedSubtree(
                        key: ValueKey(AuthorizationSession.scopeKey),
                        child: child),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// UI routing supplements the API's authorization checks, including deep links.
String? mobileAccessRedirect(String path) {
  if (!AuthorizationSession.initialized || AuthorizationSession.switching) {
    return null;
  }
  if (AuthorizationSession.signedIn && AuthorizationSession.principal == null) {
    return '/workspace' == path ? null : '/workspace';
  }
  if (AuthorizationSession.signedIn &&
      !AuthorizationSession.hasRole('SHIPPER') &&
      !AuthorizationSession.hasRole('CARRIER')) {
    return path == '/workspace' ? null : '/workspace';
  }
  if (path == '/workspace') {
    return AuthorizationSession.signedIn
        ? AuthorizationSession.home
        : '/customer/login';
  }
  if (AuthorizationSession.signedIn && AuthorizationSession.principal != null) {
    if (path.startsWith('/customer') &&
        !AuthorizationSession.hasRole('SHIPPER')) {
      return AuthorizationSession.home;
    }
    if (path.startsWith('/driver') &&
        !AuthorizationSession.hasRole('CARRIER')) {
      return AuthorizationSession.home;
    }
    if (path == '/customer/login') {
      return AuthorizationSession.home;
    }
  }
  final customerPublic = [
    '/customer',
    '/customer/login',
    '/customer/register',
    '/customer/register-user',
    '/customer/trips',
    '/customer/eligible'
  ];
  final driverPublic =
      path == '/driver' || path.startsWith('/driver/onboarding/');
  if (path.startsWith('/customer') && !customerPublic.contains(path)) {
    if (!AuthorizationSession.signedIn) return '/customer/login';
    if (!AuthorizationSession.hasRole('SHIPPER')) {
      return AuthorizationSession.home;
    }
    final permission = path == '/customer/team'
        ? 'organization.member.invite'
        : path == '/customer/integrations'
            ? 'integration.manage'
            : path == '/customer/book'
                ? 'load.create'
                : 'load.read';
    if (!AuthorizationSession.can(permission)) return '/customer';
  }
  if (path.startsWith('/driver') && !driverPublic) {
    // /driver shows the same sign-in inside the carrier shell. The shipper's sign-in here swapped the shell out
    // and back mid-transition and put it in the tree twice; unconfirmed as the cause of the blank screen.
    if (!AuthorizationSession.signedIn) return '/driver';
    if (!AuthorizationSession.hasRole('CARRIER')) {
      return AuthorizationSession.home;
    }
    final permission = path == '/driver/payout-setup'
        ? 'bank_account.create_token'
        : path == '/driver/fleet'
            ? 'organization.member.invite'
            : path == '/driver/publish'
                ? 'trip.publish'
                : path.endsWith('/pod')
                    ? 'pod.upload'
                    : path.contains('payout') || path == '/driver/earnings'
                        ? 'payment.read'
                        : 'load.read';
    if (!AuthorizationSession.can(permission)) return '/driver';
    // Payment amounts are the owner's, as on Profile and the booking screen: a dispatcher holds
    // payment.read too, and only the owner may add the bank account.
    if (permission == 'payment.read' &&
        !AuthorizationSession.can('bank_account.create_token')) {
      return '/driver';
    }
  }
  return null;
}

/// Only on the access gate (no company chosen yet, or access could not load), where no app
/// screen and so no header shows; app screens switch company and sign out from its menu.
class OrganizationToolbar extends StatelessWidget {
  const OrganizationToolbar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AuthorizationSession.revision,
        builder: (context, _) => !AuthorizationSession.signedIn
            ? const SizedBox.shrink()
            : SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: AuthorizationSession.organizationId,
                        hint: const Text('Choose company'),
                        underline: const SizedBox.shrink(),
                        items: AuthorizationSession.organizations
                            .map((o) => DropdownMenuItem(
                                  value: o['id'] as String,
                                  child: Text(
                                      o['displayName'] as String? ??
                                          o['id'] as String,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (id) {
                          if (id != null) {
                            AuthorizationSession.selectOrganization(id);
                          }
                        },
                      ),
                    ),
                    const IconButton(
                        tooltip: 'Refresh',
                        onPressed: AuthorizationSession.refresh,
                        icon: Icon(Icons.refresh)),
                    const IconButton(
                        tooltip: 'Sign out of all companies',
                        onPressed: AuthorizationSession.signOut,
                        icon: Icon(Icons.logout)),
                  ]),
                ),
              ),
      );
}
