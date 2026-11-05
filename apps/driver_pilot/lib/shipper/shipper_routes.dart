import "package:flutter/widgets.dart";
import "package:go_router/go_router.dart";

import "shipper_home.dart";
import "../load_board/my_loads.dart";
import "../load_board/post_a_load.dart";
import "../sign_in_screen.dart";
import "shipper_register.dart";
import "shipper_team.dart";
import "erp_integrations.dart";
import "find_a_lane.dart";
import "book_a_lane.dart";
import "shipments_list.dart";
import "shipment_screen.dart";

List<RouteBase> customerFlowRoutes() {
  return [
    GoRoute(
      path: "/customer",
      builder: (_, __) => const CustomerHomeScreen(),
      routes: [
        GoRoute(
            path: "login",
            // An old ?phone= link drops its query, so the number leaves the address bar (see PhoneForSignIn).
            redirect: (_, state) =>
                state.uri.hasQuery ? "/customer/login" : null,
            builder: (_, state) => SignInScreen(
                startingPhone: switch (state.extra) {
              PhoneForSignIn(:final number) => number,
              _ => null,
            })),
        GoRoute(
            path: "register",
            builder: (_, __) => const CustomerRegisterScreen()),
        GoRoute(
            path: "register-user",
            builder: (_, __) => const CustomerRegisterUserScreen()),
        GoRoute(path: "team", builder: (_, __) => const CustomerTeamScreen()),
        GoRoute(
            path: "integrations",
            builder: (_, __) => const CustomerIntegrationsScreen()),
        GoRoute(
            path: "trips",
            builder: (_, state) => CustomerTripsScreen(
                startWithMatch: state.uri.queryParameters["tab"] == "match")),
        // Booking starts from a lane card: a Book screen with no lane is how stale prices and
        // guessed weights happened (spec/decisions.md).
        GoRoute(
            path: "book",
            redirect: (_, state) =>
                (state.uri.queryParameters["anchorTripId"] ?? "").isEmpty
                    ? "/customer/trips"
                    : null,
            builder: (_, state) =>
                CustomerBookShipmentScreen.fromQuery(state.uri.queryParameters,
                    extra: state.extra)),
        // Post a load opens from a search that found nothing, which hands over its places in memory; a reload has
        // none, so it goes back to the search.
        GoRoute(
            path: "post-load",
            redirect: (_, state) =>
                state.extra is LoadToPost ? null : "/customer/trips?tab=match",
            builder: (_, state) =>
                PostALoadScreen(search: state.extra as LoadToPost)),
        GoRoute(path: "loads", builder: (_, __) => const MyLoadsScreen()),
        GoRoute(
          path: "eligible",
          redirect: (_, __) => "/customer/trips?tab=match",
        ),
        GoRoute(
            path: "shipments",
            builder: (_, __) => const CustomerShipmentsScreen()),
        GoRoute(
          path: "shipments/:shipmentId",
          // Keyed by the id: go_router keeps one page per path pattern, so moving from one shipment
          // to another (as a notice's View does) would otherwise keep the first one's screen.
          builder: (_, state) => CustomerShipmentDetailScreen(
              key: ValueKey(state.pathParameters["shipmentId"]),
              shipmentId: state.pathParameters["shipmentId"] ?? ""),
        ),
      ],
    ),
  ];
}
