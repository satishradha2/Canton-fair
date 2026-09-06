import 'dart:convert';
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'business_card_parser.dart';
import 'card_crop_text_check.dart';
import 'team_workspace_service.dart';

/// App-owned originals and OCR output survive leaving the screen or restarting.
/// The draft is not a supplier record until the user completes capture.
class BusinessCardCapture {
  BusinessCardCapture._(this.scope, this.id, this.directory, this.pointer);

  final String scope;
  final String id;
  final Directory directory;
  final File pointer;
  final Map<String, Map<String, dynamic>> sides = {};
  final Map<String, String> fields = {};
  final Set<String> edited = {};
  final List<Map<String, dynamic>> aiReadings = [];
  String mode = 'Chinese + English';
  String? pendingSide;
  bool backBlank = false;
  int? supplierDestination;
  Future<void> _writes = Future<void>.value();

  static const modes = [
    'Chinese + English', 'Latin', 'Japanese + English',
    'Korean + English', 'Devanagari + English',
  ];

  static Future<BusinessCardCapture> open() async {
    final scope = await TeamWorkspaceService().scopeKey();
    final root = await getApplicationDocumentsDirectory();
    final base = Directory(p.join(root.path, 'attachments', scope, 'business_cards'));
    await base.create(recursive: true);
    final pointer = File(p.join(base.path, 'current.json'));
    if (await pointer.exists()) {
      final id = (jsonDecode(await pointer.readAsString()) as Map)['id'] as String;
      if (!RegExp(r'^card_[0-9]+$').hasMatch(id)) {
        throw const FormatException('Invalid card draft identifier');
      }
      final draft = BusinessCardCapture._(scope, id, Directory(p.join(base.path, id)), pointer);
      final data = jsonDecode(await File(p.join(draft.directory.path, 'draft.json')).readAsString()) as Map;
      draft.mode = modes.contains(data['mode']) ? data['mode'] as String : modes.first;
      draft.backBlank = data['back_blank'] == true;
      draft.pendingSide = data['pending_side'] as String?;
      draft.fields.addAll(Map<String, String>.from(data['fields'] as Map? ?? {}));
      draft.edited.addAll((data['edited'] as List? ?? []).cast<String>());
      draft.aiReadings.addAll((data['ai_readings'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map)));
      for (final entry in (data['sides'] as Map? ?? {}).entries) {
        draft.sides[entry.key as String] = Map<String, dynamic>.from(entry.value as Map);
      }
      return draft;
    }
    final id = 'card_${DateTime.now().microsecondsSinceEpoch}';
    final draft = BusinessCardCapture._(scope, id, Directory(p.join(base.path, id)), pointer);
    await draft.directory.create(recursive: true);
    await draft.save();
    await pointer.writeAsString(jsonEncode({'id': id}), flush: true);
    return draft;
  }

  Future<void> save() {
    final snapshot = jsonEncode({
      'id': id, 'mode': mode, 'back_blank': backBlank,
      'pending_side': pendingSide, 'fields': fields,
      'edited': edited.toList(), 'sides': sides, 'ai_readings': aiReadings,
    });
    final next = _writes.then((_) async {
      final temporary = File(p.join(directory.path, 'draft.next.json'));
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(p.join(directory.path, 'draft.json'));
    });
    _writes = next.catchError((Object _) {});
    return next;
  }

  String imagePath(String side) {
    final name = sides[side]?['file'] as String? ?? '';
    if (name.isEmpty || p.basename(name) != name) return '';
    return p.join(directory.path, name);
  }

  Future<void> keepImage(String side, String source) async {
    if (side != 'front' && side != 'back') throw ArgumentError.value(side);
    final extension = p.extension(source).toLowerCase();
    final suffix = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension) ? extension : '.jpg';
    final filename = '${side}_${DateTime.now().microsecondsSinceEpoch}$suffix';
    await File(source).copy(p.join(directory.path, filename));
    sides[side] = {
      'file': filename, 'captured_at': DateTime.now().toUtc().toIso8601String(),
      'passes': <String, dynamic>{}, 'warnings': <String>[],
    };
    if (side == 'back') backBlank = false;
    pendingSide = null;
    await save();
  }

  String readingPath(String side) {
    final corrected = sides[side]?['processed_file'] as String?;
    if (corrected == null || p.basename(corrected) != corrected ||
        sides[side]?['crop_verified'] != true) {
      return imagePath(side);
    }
    return p.join(directory.path, corrected);
  }

  Future<void> useCrop(String side, String path) async {
    final resolvedDirectory = await directory.resolveSymbolicLinks();
    final resolvedImage = await File(path).resolveSymbolicLinks();
    if (!sides.containsKey(side) ||
        !p.equals(p.dirname(resolvedImage), resolvedDirectory) ||
        !await File(resolvedImage).exists()) {
      throw StateError('The corrected image is not in this card draft.');
    }
    sides[side]!['processed_file'] = p.basename(resolvedImage);
    sides[side]!['crop_verified'] = false;
    await save();
  }

  Map<String, String> get imageIdentities => {
    for (final side in sides.keys) side: p.basename(readingPath(side)),
  };

  bool matchesAi(Map<String, dynamic> reading) {
    final inputs = reading['input_files'] as Map? ?? {};
    final current = imageIdentities;
    return inputs.length == current.length &&
        current.entries.every((entry) => inputs[entry.key] == entry.value);
  }

  String translationSource(String side) {
    for (final reading in aiReadings.reversed) {
      if (reading['operation'] == 'extract' && matchesAi(reading)) {
        final transcript = reading['transcript'] as Map?;
        final text = transcript?[side] as String?;
        if (text != null && text.trim().isNotEmpty) return text;
      }
    }
    return sideText(side);
  }

  Future<void> readSide(String side) async {
    final page = sides[side];
    if (page == null) return;
    final scripts = <TextRecognitionScript>[
      TextRecognitionScript.latin,
      if (mode == 'Chinese + English') TextRecognitionScript.chinese,
      if (mode == 'Japanese + English') TextRecognitionScript.japanese,
      if (mode == 'Korean + English') TextRecognitionScript.korean,
      if (mode == 'Devanagari + English') TextRecognitionScript.devanagiri,
    ];
    final warnings = <String>[];
    Future<Map<String, dynamic>> recognize(String path, String source) async {
      final passes = <String, dynamic>{};
      for (final script in scripts) {
        final recognizer = TextRecognizer(script: script);
        try {
          final result = await recognizer.processImage(InputImage.fromFilePath(path));
          passes[script.name] = {
            'text': result.text,
            'input_file': p.basename(path),
            'lines': [for (final block in result.blocks) for (final line in block.lines) {
              'text': line.text,
              'box': [line.boundingBox.left, line.boundingBox.top,
                line.boundingBox.right, line.boundingBox.bottom],
              'languages': line.recognizedLanguages,
            }],
          };
        } catch (_) {
          warnings.add('${script.name} recognition failed for the $source. Original preserved; retry reading.');
        } finally {
          await recognizer.close();
        }
      }
      return passes;
    }

    // Never use an unverified crop for cloud extraction. Verification is an
    // OCR-based safeguard, not proof that every printed character was detected.
    page['crop_verified'] = false;
    final originals = await recognize(imagePath(side), 'original');
    page['original_passes'] = originals;
    var selected = originals;
    final corrected = page['processed_file'] as String?;
    if (corrected != null && p.basename(corrected) == corrected) {
      final cropped = await recognize(p.join(directory.path, corrected), 'crop');
      page['crop_passes'] = cropped;
      final check = CardCropTextCheck.evaluate(originals: originals, cropped: cropped,
          requiredScripts: scripts.map((script) => script.name).toSet());
      final verified = check.verified;
      page['crop_verified'] = verified;
      page['crop_check'] = {
        'method': 'original-versus-crop-ocr-v1',
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'missing_lines': check.missingLines,
        'complete': check.complete,
      };
      if (verified) {
        selected = cropped;
      } else {
        warnings.add('Using the original: the crop could not be confirmed to retain all readable text. Both images and recognition results are preserved.');
      }
    }
    final previous = Map<String, dynamic>.from(page['passes'] as Map? ?? {});
    // Keep prior output in the archive, but never mix an old crop's text into
    // the active result for a different input image.
    if (previous.isNotEmpty) {
      final history = List<dynamic>.from(page['reading_history'] as List? ?? []);
      history.add({'read_at': page['read_at'], 'passes': previous});
      page['reading_history'] = history;
    }
    final currentInput = p.basename(readingPath(side));
    page['passes'] = {
      for (final entry in previous.entries)
        if ((entry.value as Map)['input_file'] == currentInput) entry.key: entry.value,
      ...selected,
    };
    page['mode'] = mode;
    page['read_at'] = DateTime.now().toUtc().toIso8601String();
    page['warnings'] = warnings;
    if (sideText(side).trim().length < 20) {
      warnings.add('Very little text detected. Check focus, lighting and card edges, or enter details manually.');
    }
    updateSuggestions();
    await save();
  }

  String sideText(String side) {
    final passes = sides[side]?['passes'] as Map? ?? {};
    final lines = <String>{};
    for (final pass in passes.values) {
      lines.addAll(((pass as Map)['text'] as String? ?? '')
          .split(RegExp(r'[\r\n]+')).map((line) => line.trim())
          .where((line) => line.isNotEmpty));
    }
    return lines.join('\n');
  }

  String get text => ['front', 'back'].map(sideText).where((s) => s.isNotEmpty).join('\n\n');
  Map<String, List<String>> get candidates => BusinessCardParser.candidates(text);

  void updateSuggestions() {
    final values = candidates;
    final suggestions = <String, String>{
      for (final entry in values.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value.first,
      'otherEmails': (values['email'] ?? []).skip(1).join('\n'),
      'otherPhones': (values['phone'] ?? []).skip(1).join('\n'),
      'websites': (values['websites'] ?? []).join('\n'),
      'address': (values['address'] ?? []).join('\n'),
      'social': (values['social'] ?? []).join('\n'),
    };
    for (final key in {...fields.keys, ...suggestions.keys}) {
      if (!edited.contains(key)) fields[key] = suggestions[key] ?? '';
    }
    applyLatestAi();
  }

  int applyLatestAi() {
    for (final reading in aiReadings.reversed) {
      if (reading['operation'] != 'extract' || !matchesAi(reading)) continue;
      var count = 0;
      for (final entry in (reading['fields'] as Map? ?? {}).entries) {
        if (entry.key is! String || entry.value is! String) continue;
        final key = entry.key as String;
        final value = (entry.value as String).trim();
        if (edited.contains(key) || value.isEmpty || fields[key] == value) continue;
        fields[key] = value;
        count++;
      }
      return count;
    }
    return 0;
  }

  Map<String, dynamic> archive({Map<String, String>? reviewedFields}) => {
    'version': 1, 'id': id, 'engine': 'ML Kit on-device',
    'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    'fields': reviewedFields ?? Map<String, String>.from(fields),
    'candidates': candidates, 'back_blank': backBlank,
    'sides': jsonDecode(jsonEncode(sides)), 'raw_text': text,
    'ai_readings': jsonDecode(jsonEncode(aiReadings)),
  };

  Future<void> markSaved() async {
    await _writes;
    if (await pointer.exists()) {
      final data = jsonDecode(await pointer.readAsString()) as Map;
      if (data['id'] == id) await pointer.delete();
    }
  }
}
