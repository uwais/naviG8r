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
                                  : 'Organization access',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Text(AuthorizationSession.error ??
                              (internal
                                  ? 'Use the operations portal for Finance, Operations, and Admin work. Select a shipper or carrier organization above to use its mobile workspace.'
                                  : AuthorizationSession.organizations.isEmpty
                                      ? 'You have no active organization membership. Contact your organization administrator.'
                                      : AuthorizationSession.principal == null
                                          ? 'Choose an organization above to continue.'
                                          : 'You have no mobile permissions in this organization. Contact your organization administrator.')),
                          if (internal) ...[
                            const SizedBox(height: 12),
                            SelectableText(
                                '${api.baseUrl.replaceFirst(RegExp(r"/api/?$"), "")}/ops'),
                          ],
                          if (AuthorizationSession.error != null)
                            const TextButton(
                                onPressed: AuthorizationSession.refresh,
                                child: Text('Retry')),
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
    if (path == '/customer/login' || path == '/driver/onboarding/otp') {
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
    if (!AuthorizationSession.signedIn) return '/driver/onboarding/phone';
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
  }
  return null;
}

/// Placed inside each route's app bar so screen readers can reach the selector.
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
                        hint: const Text('Choose organization'),
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
                        tooltip: 'Refresh access',
                        onPressed: AuthorizationSession.refresh,
                        icon: Icon(Icons.refresh)),
                    const IconButton(
                        tooltip: 'Sign out of all organizations',
                        onPressed: AuthorizationSession.signOut,
                        icon: Icon(Icons.logout)),
                  ]),
                ),
              ),
      );
}
