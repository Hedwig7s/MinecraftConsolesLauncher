import 'dart:convert';
import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:minecraft_consoles_updater/backend.dart';

part 'updateinfo.g.dart';

@JsonSerializable()
class UpdateInfo {
  const UpdateInfo({required this.lastUpdate, required this.gameFiles});
  final DateTime lastUpdate;
  final List<String> gameFiles;

  factory UpdateInfo.fromJson(Map<String, Object?> json) =>
      _$UpdateInfoFromJson(json);

  Map<String, dynamic> toJson() => _$UpdateInfoToJson(this);

  Future<void> save() async {
    final json = toJson();
    await File(
      '$target/updateinfo.json',
    ).writeAsString(jsonEncode(json)); // FIXME: Shouldn't be hardcoded
  }

  static Future<UpdateInfo> load() async {
    final file = File('$target/updateinfo.json');
    if (!await file.exists()) {
      return UpdateInfo(
        lastUpdate: DateTime.fromMillisecondsSinceEpoch(0),
        gameFiles: [],
      );
    }
    final json = await file.readAsString();
    return UpdateInfo.fromJson(jsonDecode(json));
  }
}
