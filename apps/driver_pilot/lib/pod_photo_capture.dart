import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:image_picker/image_picker.dart";

import "pilot_api.dart";
import "ui/nv_button.dart";
import "ui/nv_message.dart";
import "ui/tokens.dart";

/// Opens the camera or the phone's photos and gives back the picture, or null if the driver backs out. Tests replace
/// it, since a widget test cannot open the real plugin. 1600 px wide at quality 70 keeps a phone photo of a
/// delivery note readable and well under the server's 1.5 MB limit.
@visibleForTesting
Future<Uint8List?> Function(ImageSource source) pickPodPhoto =
    _pickWithImagePicker;

Future<Uint8List?> _pickWithImagePicker(ImageSource source) async {
  final file = await ImagePicker()
      .pickImage(source: source, maxWidth: 1600, imageQuality: 70);
  return file?.readAsBytes();
}

const podPhotoLimit = 3;
const _podPhotoMaxBytes = 1572864;

/// The type the server takes, read from the picture's first bytes as the server reads it; null for any other.
String? podPhotoContentType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return "image/jpeg";
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      String.fromCharCodes(bytes.sublist(1, 4)) == "PNG") {
    return "image/png";
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == "RIFF" &&
      String.fromCharCodes(bytes.sublist(8, 12)) == "WEBP") {
    return "image/webp";
  }
  return null;
}

/// A photo the server has. [bytes] is null for one sent before this screen opened: the screen shows a tile for it.
class SentPodPhoto {
  const SentPodPhoto(this.id, this.bytes);
  final String id;
  final Uint8List? bytes;
}

/// The photos for one delivery while the driver adds them. Each is sent as soon as it is picked, so Confirm
/// delivery waits on nothing but the notes.
class PodPhotoDraft extends ChangeNotifier {
  PodPhotoDraft(this.shipmentId, {required this.refusalSentence});
  final String shipmentId;

  /// The screen's own words for a refusal no photo sentence covers, such as the trip no longer being the driver's.
  final String Function(Object error) refusalSentence;

  final List<SentPodPhoto> photos = [];
  bool sending = false;
  String? error;
  bool _disposed = false;

  /// Photos the server already lists for this delivery, sent from an earlier visit to the screen.
  void addAlreadySent(Iterable<String> ids) {
    for (final id in ids) {
      if (!photos.any((photo) => photo.id == id)) {
        photos.add(SentPodPhoto(id, null));
      }
    }
    _changed();
  }

  Future<void> take(ImageSource source) async {
    error = null;
    Uint8List? bytes;
    try {
      bytes = await pickPodPhoto(source);
    } catch (_) {
      error = source == ImageSource.camera
          ? "Could not open the camera. Allow NaviG8r to use it in your phone settings."
          : "Could not open your photos. Allow NaviG8r to use them in your phone settings.";
    }
    final contentType = bytes == null ? null : podPhotoContentType(bytes);
    if (bytes != null && contentType == null) {
      error =
          "This file is not a photo the app can send. Take a photo instead.";
    } else if (bytes != null && bytes.length > _podPhotoMaxBytes) {
      error = "This photo is too large to send. Take it again.";
    }
    if (bytes == null || contentType == null || error != null) {
      _changed();
      return;
    }
    sending = true;
    _changed();
    try {
      final response = await api.dio.post<Map<String, dynamic>>(
          "/v1/shipments/$shipmentId/pod-photos",
          data: bytes,
          options: Options(contentType: contentType));
      final photo = response.data?["photo"];
      final id = photo is Map ? photo["id"] : null;
      if (id is String) {
        photos.add(SentPodPhoto(id, bytes));
      } else {
        error = "Could not send the photo. Try again.";
      }
    } catch (e) {
      error = _sendRefusal(e);
    } finally {
      sending = false;
      _changed();
    }
  }

  Future<void> remove(SentPodPhoto photo) async {
    error = null;
    sending = true;
    _changed();
    try {
      await api.dio.delete<Map<String, dynamic>>(
          "/v1/shipments/$shipmentId/pod-photos/${photo.id}");
      photos.remove(photo);
    } catch (e) {
      error = serverNeverAnswered(e)
          ? "Could not remove the photo: no signal. Try again when you have one."
          : _sendRefusal(e);
    } finally {
      sending = false;
      _changed();
    }
  }

  String _sendRefusal(Object e) {
    if (serverNeverAnswered(e)) {
      return "Could not send the photo: no signal. Try again when you have one.";
    }
    final body = e is DioException ? e.response?.data : null;
    return switch (body is Map ? body["error"] : null) {
      "pod_photo_too_large" =>
        "This photo is too large to send. Take it again.",
      "pod_photo_wrong_type" =>
        "This file is not a photo the app can send. Take a photo instead.",
      "pod_photo_limit" =>
        "This delivery already has 3 photos. Remove one to add another.",
      "pod_photos_closed" =>
        "Delivery is already confirmed, so the photos cannot change.",
      _ => refusalSentence(e),
    };
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// dr-confirm, step 1: the photos added so far, each with Remove, then Take photo and Choose from gallery until
/// there are three.
class PodPhotoCapture extends StatelessWidget {
  const PodPhotoCapture(
      {required this.draft, this.forDriver = false, super.key});
  final PodPhotoDraft draft;
  final bool forDriver;

  /// For a photo sent before the screen opened, whose picture this phone no longer has.
  static const _sentEarlier = ColoredBox(
      color: NvColors.sunken,
      child: Center(child: Text("Sent", style: NvText.caption)));

  Widget _tile(SentPodPhoto photo, int number) {
    final bytes = photo.bytes;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        image: true,
        label: "Photo $number",
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NvRadius.sm),
          child: SizedBox.square(
            dimension: 96,
            child: bytes == null
                ? _sentEarlier
                : Image.memory(bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _sentEarlier),
          ),
        ),
      ),
      if (!draft.sending)
        NvButton(
          label: "Remove",
          semanticsLabel: "Remove photo $number",
          kind: NvButtonKind.quiet,
          onPressed: () => draft.remove(photo),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final photos = draft.photos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: NvSpace.s2),
        if (photos.isEmpty)
          const Text(
              "Take a photo of the signed delivery note or the goods. Up to 3 photos.",
              style: NvText.body)
        else ...[
          Text(
              photos.length == 1
                  ? "Photo added"
                  : "${photos.length} photos added",
              style: NvText.bodyStrong),
          const SizedBox(height: NvSpace.s2),
          Wrap(spacing: NvSpace.s3, runSpacing: NvSpace.s2, children: [
            for (final (index, photo) in photos.indexed)
              _tile(photo, index + 1),
          ]),
        ],
        if (draft.error != null) ...[
          const SizedBox(height: NvSpace.s3),
          NvMessage(draft.error!, tone: NvMessageTone.problem),
        ],
        const SizedBox(height: NvSpace.s3),
        if (draft.sending)
          const Row(children: [
            SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: NvSpace.s2),
            Text("Sending", style: NvText.body),
          ])
        else if (photos.length < podPhotoLimit) ...[
          NvButton(
            label: "Take photo",
            kind: NvButtonKind.secondary,
            forDriver: forDriver,
            fullWidth: true,
            onPressed: () => draft.take(ImageSource.camera),
          ),
          const SizedBox(height: NvSpace.s2),
          NvButton(
            label: "Choose from gallery",
            kind: NvButtonKind.secondary,
            forDriver: forDriver,
            fullWidth: true,
            onPressed: () => draft.take(ImageSource.gallery),
          ),
        ],
      ],
    );
  }
}
