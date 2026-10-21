import "package:flutter/widgets.dart";
import "package:go_router/go_router.dart";

import "shipper_home.dart";
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
            builder: (_, state) => SignInScreen(
                startingPhone: state.uri.queryParameters["phone"])),
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
