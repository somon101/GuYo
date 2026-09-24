import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';

/// The one way this app draws an image that came from the backend:
/// disk-cached, decoded no larger than it is actually shown, and NEVER
/// deformed.
///
/// The bug this exists to make impossible: asking for a decode with BOTH
/// a width and a height (CachedNetworkImage's `memCacheWidth` +
/// `memCacheHeight`) resizes the bitmap to exactly those two numbers and
/// throws the source's aspect ratio away -- Flutter's own docs call that
/// case "similar to BoxFit.fill". A 1458x829 rank badge was therefore
/// physically squeezed into a square *before* any BoxFit ran, which is
/// why the square artworks (Бронза, Грандмастер) looked right and every
/// wide one looked crushed, and why no `fit:` could undo it.
///
/// [ResizeImagePolicy.fit] scales the decode to fit INSIDE the box while
/// keeping the aspect ratio, so memory stays bounded (the reason the
/// decode was capped in the first place) without deforming anything.
///
/// Anything rendering a backend image should go through this rather than
/// reaching for CachedNetworkImage directly, so the same mistake cannot
/// reappear in a fifth place.
class RemoteImage extends StatelessWidget {
  /// Backend-relative path, e.g. "/media/ranks/icons/x.png" -- resolved
  /// through ApiClient, never a hand-built absolute URL.
  final String url;

  /// The box the image is laid out in. Either may be null (or infinite)
  /// when the parent decides that axis; the decode budget then follows
  /// whichever dimension is known.
  final double? width;
  final double? height;

  final BoxFit fit;

  /// Drawn while loading and if the image can't be loaded at all.
  final Widget Function() fallbackBuilder;

  const RemoteImage({
    super.key,
    required this.url,
    required this.fallbackBuilder,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  /// A cover crop keeps only the middle of the image, so fitting the
  /// decode exactly inside the box would leave the cropped axis short and
  /// force an upscale. Decoding a little larger than the box costs very
  /// little at avatar sizes and keeps a portrait or landscape photo sharp
  /// after the crop. `contain` needs no such margin -- the whole image is
  /// visible, so the box IS the budget.
  static const double _coverOversample = 1.6;

  int? _budget(double? logical, double devicePixelRatio) {
    if (logical == null || !logical.isFinite || logical <= 0) return null;
    final scale = fit == BoxFit.cover ? _coverOversample : 1.0;
    return (logical * devicePixelRatio * scale).round();
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return fallbackBuilder();

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = _budget(width, dpr);
    final decodeHeight = _budget(height, dpr);

    ImageProvider provider = CachedNetworkImageProvider(ApiClient.instance.mediaUrl(url));
    if (decodeWidth != null || decodeHeight != null) {
      provider = ResizeImage(
        provider,
        width: decodeWidth,
        height: decodeHeight,
        // The whole point -- see this class's doc comment.
        policy: ResizeImagePolicy.fit,
        // Never decode bigger than the file really is; a small icon stays
        // small in memory instead of being blown up to the box.
        allowUpscaling: false,
      );
    }

    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      // Better resampling when a large badge is drawn small, which is the
      // normal case for every icon in this app.
      filterQuality: FilterQuality.medium,
      // Keeps the previous frame during a reload instead of flashing empty.
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return fallbackBuilder();
      },
      errorBuilder: (_, _, _) => fallbackBuilder(),
    );
  }
}
