import 'package:flutter/material.dart';

import 'remote_image.dart';

/// A catalog id (frames, badges and titles are pictures the admin uploaded) is plain digits;
/// older looks were words.
bool isCatalogKey(String? key) => key != null && key.isNotEmpty && int.tryParse(key) != null;

/// The picture of one catalog item, from the server (cached on the phone).
class CosmeticImage extends StatelessWidget {
  final String artKey;
  final double? width;
  final double? height;
  const CosmeticImage(this.artKey, {super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) => RemoteImage(
        url: '/cosmetics/art/$artKey',
        width: width,
        height: height,
        fallbackBuilder: () => SizedBox(width: width, height: height),
      );
}

/// A title: the empty ribbon picture with the name written on it in the person's language.
class TitleRibbon extends StatelessWidget {
  final String? artKey;
  final String text;
  final double width;
  const TitleRibbon({super.key, required this.artKey, required this.text, this.width = 190});

  @override
  Widget build(BuildContext context) {
    final height = width * 0.336;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(alignment: Alignment.center, children: [
        if (isCatalogKey(artKey)) Positioned.fill(child: CosmeticImage(artKey!, width: width, height: height)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.27),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: width * 0.075, shadows: const [Shadow(color: Colors.black87, blurRadius: 3)]),
            ),
          ),
        ),
      ]),
    );
  }
}
