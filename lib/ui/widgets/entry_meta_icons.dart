import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class EntryMetaVisual {
  const EntryMetaVisual({
    required this.icon,
    required this.notes,
    required this.hasValue,
  });

  final IconData icon;
  final String notes;
  final bool hasValue;
}

const _moodIconMap = <String, IconData>{
  '🙂': LucideIcons.smile,
  '😄': LucideIcons.laugh,
  '🥰': LucideIcons.heart,
  '😌': LucideIcons.sparkles,
  '😐': LucideIcons.meh,
  '😞': LucideIcons.frown,
};

const _weatherIconMap = <String, IconData>{
  '☀️': LucideIcons.sun,
  '☀': LucideIcons.sun,
  '🌤️': LucideIcons.cloudSun,
  '🌤': LucideIcons.cloudSun,
  '⛅': LucideIcons.cloudy,
  '🌧️': LucideIcons.cloudRain,
  '🌧': LucideIcons.cloudRain,
  '❄️': LucideIcons.cloudSnow,
  '❄': LucideIcons.cloudSnow,
  '🌫️': LucideIcons.cloudFog,
  '🌫': LucideIcons.cloudFog,
};

EntryMetaVisual parseMoodMeta(String raw) {
  return _parseMeta(raw, _moodIconMap, LucideIcons.smile);
}

EntryMetaVisual parseWeatherMeta(String raw) {
  return _parseMeta(raw, _weatherIconMap, LucideIcons.cloudSun);
}

EntryMetaVisual _parseMeta(
  String raw,
  Map<String, IconData> iconMap,
  IconData fallbackIcon,
) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return EntryMetaVisual(icon: fallbackIcon, notes: '', hasValue: false);
  }

  for (final symbol in iconMap.keys) {
    if (trimmed.startsWith(symbol)) {
      return EntryMetaVisual(
        icon: iconMap[symbol]!,
        notes: trimmed.substring(symbol.length).trim(),
        hasValue: true,
      );
    }
  }

  for (final symbol in iconMap.keys) {
    final index = trimmed.indexOf(symbol);
    if (index >= 0) {
      return EntryMetaVisual(
        icon: iconMap[symbol]!,
        notes: trimmed.replaceFirst(symbol, '').trim(),
        hasValue: true,
      );
    }
  }

  return EntryMetaVisual(icon: fallbackIcon, notes: trimmed, hasValue: true);
}
