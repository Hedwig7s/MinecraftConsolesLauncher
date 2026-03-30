// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'updateinfo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateInfo _$UpdateInfoFromJson(Map<String, dynamic> json) => UpdateInfo(
  lastUpdate: DateTime.parse(json['lastUpdate'] as String),
  gameFiles: (json['gameFiles'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$UpdateInfoToJson(UpdateInfo instance) =>
    <String, dynamic>{
      'lastUpdate': instance.lastUpdate.toIso8601String(),
      'gameFiles': instance.gameFiles,
    };
