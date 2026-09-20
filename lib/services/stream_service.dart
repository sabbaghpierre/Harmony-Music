import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider(
      {required this.playable, this.audioFormats, this.statusMSG = ""});

  static Future<StreamProvider> fetch(String videoId,
      {String? ytDlpPath}) async {
    // Prefer resolving via yt-dlp: its URLs carry the PO token / signature
    // that lets the CDN serve the whole file. Token-less androidSdkless URLs
    // only serve the first ~1MB (403 for any larger/open range), which breaks
    // playback. Falls back to getManifest below (used on platforms where
    // yt-dlp is unavailable, e.g. Android).
    final ytDlpUrl = await _resolveWithYtDlp(videoId, ytDlpPath: ytDlpPath);
    if (ytDlpUrl != null) {
      return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: [
            Audio(
                itag: _itagFromUrl(ytDlpUrl),
                audioCodec: ytDlpUrl.contains("webm") ||
                        ytDlpUrl.contains("mime=audio%2Fwebm")
                    ? Codec.opus
                    : Codec.mp4a,
                bitrate: 0,
                duration: 0,
                loudnessDb: 0.0,
                url: ytDlpUrl,
                size: _sizeFromUrl(ytDlpUrl))
          ]);
    }

    final yt = YoutubeExplode();
    
    try {
      final res = await yt.videos.streamsClient.getManifest(videoId);
      final audio = res.audioOnly;
      return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: audio
              .map((e) => Audio(
                  itag: e.tag,
                  audioCodec:
                      e.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
                  bitrate: e.bitrate.bitsPerSecond,
                  duration: 0,
                  loudnessDb: 0.0,
                  url: e.url.toString(),
                  size: e.size.totalBytes))
              .toList());
    } catch (e) {
      if (e is SocketException) {
        return StreamProvider(
          playable: false,
          statusMSG: "networkError",
        );
      } else if (e is VideoUnplayableException) {
        return StreamProvider(
          playable: false,
          statusMSG: e.message,
        );
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song requires purchase",
        );
      } else if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song is unavailable",
        );
      } else if (e is YoutubeExplodeException) {
        return StreamProvider(
          playable: false,
          statusMSG: e.message,
        );
      } else {
        return StreamProvider(
          playable: false,
          statusMSG: "Unknown error occurred",
        );
      }
    }
  }

  Audio? get highestQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 140,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateMp4aAudio =>
      audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateOpusAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250,
          orElse: () => audioFormats!.first);

  Audio? get lowQualityAudio =>
      audioFormats?.lastWhere((item) => item.itag == 249 || item.itag == 139,
          orElse: () => audioFormats!.first);

  static Future<String?> _resolveWithYtDlp(String videoId,
      {String? ytDlpPath}) async {
    for (final bin in _ytDlpBinCandidates(ytDlpPath)) {
      final url = await _runYtDlp(bin, videoId);
      if (url != null) return url;
    }
    return null;
  }

  static List<String> _ytDlpBinCandidates(String? ytDlpPath) {
    if (ytDlpPath != null && ytDlpPath.trim().isNotEmpty) {
      return <String>{
        ytDlpPath.trim(),
        'yt-dlp',
        '/usr/local/bin/yt-dlp',
      }.toList();
    }
    try {
      final box = Hive.box("AppPrefs");
      final configured = box.get("ytDlpPath");
      final home = Platform.environment['HOME'] ?? '';
      return <String>{
        if (configured is String && configured.trim().isNotEmpty)
          configured.trim(),
        'yt-dlp',
        if (home.isNotEmpty) '$home/.local/bin/yt-dlp',
        '/usr/local/bin/yt-dlp',
      }.toList();
    } catch (_) {
      return const ['yt-dlp'];
    }
  }

  static Future<String?> _runYtDlp(String bin, String videoId) async {
    try {
      final res = await Process.run(
        bin,
        [
          '--ignore-config',
          '--no-playlist',
          '--no-warnings',
          '-f',
          'ba/b',
          '-g',
          'https://music.youtube.com/watch?v=$videoId',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 20));
      if (res.exitCode != 0) return null;
      final line = (res.stdout as String)
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .firstWhere((e) => e.startsWith('http'), orElse: () => '');
      if (line.isEmpty) return null;
      final uri = Uri.tryParse(line);
      if (uri == null ||
          uri.scheme != 'https' ||
          !uri.host.endsWith('googlevideo.com')) {
        return null;
      }
      return line;
    } catch (_) {
      return null;
    }
  }

  static int _itagFromUrl(String url) {
    final match = RegExp(r'[?&]itag=(\d+)').firstMatch(url);
    return match == null ? 251 : int.tryParse(match.group(1)!) ?? 251;
  }

  static int _sizeFromUrl(String url) {
    final match = RegExp(r'[?&]clen=(\d+)').firstMatch(url);
    return match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
  }

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  Audio(
      {required this.itag,
      required this.audioCodec,
      required this.bitrate,
      required this.duration,
      required this.loudnessDb,
      required this.url,
      required this.size});

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size
      };

  factory Audio.fromJson(json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a")
          ? Codec.mp4a
          : Codec.opus,
      itag: json['itag'],
      duration: json["approxDurationMs"] ?? 0,
      bitrate: json["bitrate"] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json["size"] ?? 0);
}

enum Codec { mp4a, opus }
