import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:github/github.dart';
import 'package:minecraft_consoles_updater/updateinfo.dart';

enum InstallState { notStarted, downloading, extracting, completed }

class ProgressUpdate {
  final InstallState state;
  final int progress;
  final String? message;

  const ProgressUpdate(this.state, this.progress, [this.message]);
}

final GitHub github = GitHub();
// TODO: Make these configurable
final String target = ".${Platform.pathSeparator}Game";
final String downloadTarget = "$target${Platform.pathSeparator}Latest.zip";
final String updateInfoPath =
    "$target${Platform.pathSeparator}update_info.json";

Future<Release> getRelease() async {
  final releases = await github.repositories
      .listReleases(RepositorySlug('MCLCE', 'MinecraftConsoles')) // FIXME: Shouldn't be hardcoded, should probably be a variable elsewhere
      .toList();
  return releases.firstWhere(
    (release) => release.tagName == "nightly",
    orElse: () => throw Exception("No nightly release found"),
  );
}

bool needsUpdate(Release latestRelease, UpdateInfo updateInfo) {
  return latestRelease.publishedAt != null &&
      latestRelease.publishedAt!.isAfter(updateInfo.lastUpdate);
}

Future<void> removeOldRelease(UpdateInfo updateInfo) async {
  final root = Directory(target);

  if (!await root.exists()) return;

  for (final filePath in updateInfo.gameFiles) {
    final fullPath = '$target${Platform.pathSeparator}$filePath';
    final type = await FileSystemEntity.type(fullPath);

    try {
      switch (type) {
        case FileSystemEntityType.file:
          await File(fullPath).delete();
          break;

        case FileSystemEntityType.directory:
          final dir = Directory(fullPath);
          if (await dir.list().isEmpty) {
            await dir.delete();
          }
          break;

        default:
          // ignore not found / links
          break;
      }
    } catch (e) {}
    await File(target).delete();
  }

  await _removeEmptyDirs(root);
}

Future<void> _removeEmptyDirs(Directory dir) async {
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is Directory) {
      await _removeEmptyDirs(entity);

      if (await entity.list().isEmpty) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }
}

Future<void> downloadRelease(
  Function(ProgressUpdate) callback,
  Release latestRelease,
) async {
  final dio = Dio();
  final request = await dio.downloadUri(
    // TODO: Better error messages
    Uri.parse(
      latestRelease.assets!
          .firstWhere(
            (asset) => asset.name == "LCEWindows64.zip",
            orElse: () => throw Exception(
              "No matching asset found. got: ${latestRelease.assets!.map((a) => a.name).join(", ")} ",
            ),
          )
          .browserDownloadUrl!,
    ),
    downloadTarget,
    onReceiveProgress: (received, total) {
      if (total != -1) {
        final progress = (received / total * 100).round();
        callback(ProgressUpdate(InstallState.downloading, progress));
      }
    },
  );
  if (request.statusCode != 200) {
    throw Exception("Download failed with status code ${request.statusCode}");
  }
}

Future<List<String>> extractRelease(String downloadTarget) async {
  final inputStream = InputFileStream(downloadTarget);
  final archive = ZipDecoder().decodeStream(inputStream);
  final symbolicLinks = [];
  final List<String> files = [];

  for (final file in archive) {
    files.add(file.name);
    if (file.isSymbolicLink) {
      symbolicLinks.add(file);
      continue;
    }
    if (file.isFile) {
      final outputStream = OutputFileStream('$target/${file.name}');
      file.writeContent(outputStream);
      await outputStream.close();
    } else {
      await Directory('$target/${file.name}').create(recursive: true);
    }
  }

  for (final entity in symbolicLinks) {
    final link = Link('$target/${entity.fullPathName}');
    await link.create(entity.symbolicLink!, recursive: true);
  }
  return files;
}

Future<void> _downloadUpdate(SendPort sendPort) async {
  await Directory(target).create(recursive: true);
  sendPort.send(
    ProgressUpdate(InstallState.notStarted, 0, "Checking latest version..."),
  );
  final latestRelease = await getRelease();
  final updateInfo = await UpdateInfo.load();
  if (!needsUpdate(latestRelease, updateInfo)) {
    sendPort.send(
      ProgressUpdate(InstallState.completed, 100, "Already up to date!"),
    );
    return;
  }
  sendPort.send(
    ProgressUpdate(InstallState.notStarted, 0, "Removing old release..."),
  );
  await removeOldRelease(updateInfo);
  sendPort.send(
    ProgressUpdate(InstallState.notStarted, 0, "Downloading update..."),
  );
  await downloadRelease((update) => sendPort.send(update), latestRelease);

  sendPort.send(ProgressUpdate(InstallState.extracting, 0));
  final files = await extractRelease(downloadTarget);

  await UpdateInfo(
    lastUpdate: latestRelease.publishedAt!,
    gameFiles: files,
  ).save();

  sendPort.send(ProgressUpdate(InstallState.completed, 100));
}

Future<void> downloadUpdate(SendPort sendPort) async {
  try {
    await _downloadUpdate(sendPort);
  } catch (e) {
    sendPort.send(e);
  }
}

Future<bool> commandExists(String command) async {
  final checker = Platform.isWindows ? 'where' : 'which';

  final result = await Process.run(checker, [command]);
  return result.exitCode == 0;
}

Future<void> _startGame(String exePath, {String? wineCommand}) async {
  ProcessStartMode mode = ProcessStartMode.inheritStdio;
  await Process.start(
    wineCommand ?? exePath,
    [if (wineCommand != null) exePath],
    workingDirectory: target,
    mode: mode,
  );
}

Future<void> startGame() async {
  const String exePath = "Minecraft.Client.exe";
  if (Platform.isWindows) {
    await _startGame(exePath);
  } else {
    if (await commandExists("umu-run")) {
      await _startGame(exePath, wineCommand: "umu-run");
    } else if (await commandExists("wine")) {
      await _startGame(exePath, wineCommand: "wine");
    } else {
      throw Exception("Could not find a global wine installation.");
    }
  }
}
