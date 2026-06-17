import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

import '../../widgets/loader.dart';
import '../player_controller.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(
      () => playerController.isLyricsLoading.isTrue
          ? const Center(
              child: LoadingIndicator(),
            )
          : playerController.lyricsMode.toInt() == 1
              ? Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: padding,
                    child: Obx(
                      () => TextSelectionTheme(
                        data: Theme.of(context).textSelectionTheme,
                        child: SelectableText(
                          playerController.lyrics["plainLyrics"] == "NA"
                              ? "lyricsNotAvailable".tr
                              : playerController.lyrics["plainLyrics"],
                          textAlign: TextAlign.center,
                          style: playerController.isDesktopLyricsDialogOpen
                              ? Theme.of(context).textTheme.titleMedium!
                              : Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
              : Obx(() {
                  final synced =
                      playerController.lyrics['synced']?.toString() ?? '';
                  if (synced.isEmpty) {
                    return Center(
                      child: Text(
                        "syncedLyricsNotAvailable".tr,
                        style: playerController.isDesktopLyricsDialogOpen
                            ? Theme.of(context).textTheme.titleMedium!
                            : Theme.of(context)
                                .textTheme
                                .titleMedium!
                                .copyWith(color: Colors.white),
                      ),
                    );
                  }
                  return IgnorePointer(
                    child: LyricView(
                      controller: playerController.lyricController,
                      style: LyricStyles.default1.copyWith(
                        textStyle: const TextStyle(
                            fontSize: 20, color: Colors.white70),
                        activeStyle: const TextStyle(
                            fontSize: 20, color: Colors.white),
                        translationStyle: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    ),
                  );
                }),
    );
  }
}
