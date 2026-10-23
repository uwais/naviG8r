import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "pilot_api.dart";
import "plain_error_sentence.dart";
import "ui/nv_button.dart";
import "ui/tokens.dart";

/// The ids of a shipment's proof of delivery photos, in the order they were sent.
List<String> podPhotoIds(Map<String, dynamic> shipment) => [
      for (final photo in shipment["podPhotos"] is List
          ? shipment["podPhotos"] as List
          : const [])
        if (photo is Map && photo["id"] is String) photo["id"] as String,
    ];

/// "View proof of delivery", for whoever may read the shipment: its shipper, its carrier office and the trip's
/// driver. Opens the photos on their own screen.
class PodPhotosButton extends StatelessWidget {
  const PodPhotosButton(
      {required this.shipmentId, required this.photoIds, super.key});
  final String shipmentId;
  final List<String> photoIds;

  @override
  Widget build(BuildContext context) => NvButton(
        label: "View proof of delivery",
        semanticsLabel: photoIds.length == 1
            ? "View proof of delivery, 1 photo"
            : "View proof of delivery, ${photoIds.length} photos",
        kind: NvButtonKind.secondary,
        fullWidth: true,
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                PodPhotosScreen(shipmentId: shipmentId, photoIds: photoIds))),
      );
}

/// Each photo at the width of the screen; tapping one opens it full size to zoom in on the signature.
class PodPhotosScreen extends StatelessWidget {
  const PodPhotosScreen(
      {required this.shipmentId, required this.photoIds, super.key});
  final String shipmentId;
  final List<String> photoIds;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: NvColors.page,
        appBar: AppBar(title: const Text("Proof of delivery")),
        body: ListView(
          padding: const EdgeInsets.all(NvSpace.gutter),
          children: [
            for (final (index, id) in photoIds.indexed) ...[
              if (index > 0) const SizedBox(height: NvSpace.s4),
              _PodPhoto(
                  shipmentId: shipmentId,
                  photoId: id,
                  name: photoIds.length == 1
                      ? "Photo"
                      : "Photo ${index + 1} of ${photoIds.length}"),
            ],
          ],
        ),
      );
}

class _PodPhoto extends StatefulWidget {
  const _PodPhoto(
      {required this.shipmentId, required this.photoId, required this.name});
  final String shipmentId;
  final String photoId;
  final String name;

  @override
  State<_PodPhoto> createState() => _PodPhotoState();
}

class _PodPhotoState extends State<_PodPhoto> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The route needs the sign-in, which an image address cannot carry, so the bytes come through the app's client.
  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final response = await api.dio.get<List<int>>(
          "/v1/shipments/${widget.shipmentId}/pod-photos/${widget.photoId}",
          options: Options(responseType: ResponseType.bytes));
      if (mounted) {
        setState(() => _bytes = Uint8List.fromList(response.data ?? const []));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = plainErrorSentence(e,
            "Could not load the photo. Check your connection and try again."));
      }
    }
  }

  void _openFullSize(Uint8List bytes) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
              backgroundColor: NvColors.page,
              appBar: AppBar(title: Text(widget.name)),
              body: InteractiveViewer(
                maxScale: 5,
                child: Center(
                    child: Image.memory(bytes,
                        semanticLabel: widget.name, fit: BoxFit.contain)),
              ),
            )));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.name, style: NvText.bodyStrong),
        const SizedBox(height: NvSpace.s2),
        if (_error != null) ...[
          Text(_error!, style: NvText.body),
          const SizedBox(height: NvSpace.s2),
          NvButton(
              label: "Try again",
              kind: NvButtonKind.secondary,
              onPressed: _load),
        ] else if (bytes == null)
          const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()))
        else
          Semantics(
            button: true,
            label: "${widget.name}. Open full size",
            child: InkWell(
              onTap: () => _openFullSize(bytes),
              child: ExcludeSemantics(
                child: Image.memory(bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text(
                        "This photo cannot be shown.",
                        style: NvText.body)),
              ),
            ),
          ),
      ],
    );
  }
}
