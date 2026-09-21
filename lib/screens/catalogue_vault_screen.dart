import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../data/auto_sync_service.dart';
import '../data/database.dart';
import '../data/team_workspace_service.dart';
import '../models/models.dart';

class CatalogueVaultScreen extends StatefulWidget {
  const CatalogueVaultScreen({super.key, required this.suppliers});

  final List<Exhibitor> suppliers;

  @override
  State<CatalogueVaultScreen> createState() => _CatalogueVaultScreenState();
}

class _CatalogueVaultScreenState extends State<CatalogueVaultScreen> {
  static const _picker = MethodChannel('canton_fair_crm/backup');
  static const _maximumBytes = 120 * 1024 * 1024;
  final _db = TradeDatabase.instance;
  Exhibitor? _supplier;
  bool _busy = false;
  String? _message;

  Future<void> _chooseSupplier() async {
    final supplier = await showModalBottomSheet<Exhibitor>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: widget.suppliers
              .map((item) => ListTile(
                    title: Text(item.name),
                    subtitle: Text([item.hall, item.booth]
                        .where((value) => value.isNotEmpty)
                        .join(' / ')),
                    onTap: () => Navigator.pop(context, item),
                  ))
              .toList(),
        ),
      ),
    );
    if (supplier != null && mounted) setState(() => _supplier = supplier);
  }

  Future<void> _archiveFile(File source, {
    required String sourceType,
    required String sourceValue,
    String? originalName,
  }) async {
    final supplier = _supplier;
    if (supplier?.id == null) {
      setState(() => _message = 'Choose the supplier before archiving a catalogue.');
      return;
    }
    if (!await source.exists()) {
      setState(() => _message = 'The selected catalogue file is no longer available.');
      return;
    }
    if (await source.length() > _maximumBytes) {
      setState(() => _message = 'This file is larger than 120 MB. Use a smaller supplier catalogue.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final root = await getApplicationDocumentsDirectory();
      final scope = await TeamWorkspaceService().scopeKey();
      final folder = Directory(path.join(root.path, 'catalogue_vault', scope,
          'supplier_${supplier!.id}'));
      await folder.create(recursive: true);
      final extension = path.extension(originalName ?? source.path).toLowerCase();
      final safeExtension = RegExp(r'^\.[a-z0-9]{1,12}$').hasMatch(extension)
          ? extension
          : '.bin';
      final storedName = '${DateTime.now().microsecondsSinceEpoch}$safeExtension';
      final stored = await source.copy(path.join(folder.path, storedName));
      final details = jsonEncode({
        'format': 'catalogue-vault-v1',
        'source_type': sourceType,
        'source_value': sourceValue,
        'original_name': originalName ?? path.basename(source.path),
        'archived_at': DateTime.now().toUtc().toIso8601String(),
        'archive_status': 'queued_for_sync',
      });
      await _db.addAttachment(Attachment(
        ownerType: 'exhibitor',
        ownerId: supplier.id!,
        kind: 'catalogue',
        path: stored.path,
        note: details,
        createdAt: DateTime.now(),
      ));
      await _db.logAudit('Archived supplier catalogue',
          '${supplier.name} | $sourceType | ${originalName ?? path.basename(source.path)}');
      await AutoSyncService.instance.syncIfPossible();
      if (mounted) setState(() => _message = 'Catalogue archived. It will remain on this device and sync to the private team vault when online.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not archive catalogue: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadFile() async {
    final sourcePath = await _picker.invokeMethod<String>('pickDocument');
    if (sourcePath == null) return;
    await _archiveFile(File(sourcePath),
        sourceType: 'supplier_file', sourceValue: sourcePath);
  }

  Future<void> _captureHardCopy() async {
    final photo = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 92, maxWidth: 2800);
    if (photo == null) return;
    await _archiveFile(File(photo.path),
        sourceType: 'hard_copy_photo', sourceValue: 'Captured at supplier visit');
  }

  Future<void> _downloadFromLink([String initial = '']) async {
    final link = TextEditingController(text: initial);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download supplier catalogue'),
        content: TextField(
          controller: link,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Catalogue URL',
            hintText: 'https://supplier.example/catalogue.pdf',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Download and archive')),
        ],
      ),
    );
    final raw = link.text.trim();
    if (accepted != true || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || !['http', 'https'].contains(uri.scheme)) {
      setState(() => _message = 'Enter a valid HTTPS or HTTP catalogue link.');
      return;
    }
    final supplier = _supplier;
    if (supplier?.id == null) {
      setState(() => _message = 'Choose the supplier before downloading a catalogue.');
      return;
    }
    setState(() { _busy = true; _message = null; });
    try {
      final response = await http.Client().send(http.Request('GET', uri));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Supplier server returned HTTP ${response.statusCode}.');
      }
      final declared = response.contentLength;
      if (declared != null && declared > _maximumBytes) {
        throw StateError('The supplier file is larger than 120 MB.');
      }
      final root = await getTemporaryDirectory();
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      var extension = path.extension(uri.path);
      if (extension.isEmpty) {
        extension = contentType.contains('pdf') ? '.pdf'
            : contentType.contains('html') ? '.html'
            : contentType.startsWith('image/') ? '.jpg' : '.bin';
      }
      final temporary = File(path.join(root.path,
          'catalogue_download_${DateTime.now().microsecondsSinceEpoch}$extension'));
      final sink = temporary.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > _maximumBytes) {
          await sink.close();
          try {
            await temporary.delete();
          } catch (_) {}
          throw StateError('The supplier file is larger than 120 MB.');
        }
        sink.add(chunk);
      }
      await sink.close();
      await _archiveFile(temporary,
          sourceType: 'catalogue_link', sourceValue: uri.toString(),
          originalName: path.basename(uri.path).isEmpty ? 'supplier_catalogue$extension' : path.basename(uri.path));
      try {
        await temporary.delete();
      } catch (_) {}
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not download catalogue: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanQr() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _CatalogueQrScanner()),
    );
    if (value == null || !mounted) return;
    await _downloadFromLink(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Supplier catalogue vault')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text('Keep a permanent copy of supplier catalogues',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('The original file is archived locally first, then securely synchronized with your team. The QR code or URL remains recorded as evidence, not as the only copy.'),
      const SizedBox(height: 20),
      Card(child: ListTile(
        leading: const Icon(Icons.storefront_outlined),
        title: Text(_supplier?.name ?? 'Choose supplier'),
        subtitle: Text(_supplier == null ? 'Required before archiving a catalogue.' : 'Catalogues will be saved against this supplier.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : _chooseSupplier,
      )),
      const SizedBox(height: 16),
      _vaultAction(Icons.upload_file_outlined, 'Upload supplier file',
          'PDF, Excel, images, ZIP, or any catalogue file already on this device', _uploadFile),
      _vaultAction(Icons.qr_code_scanner_outlined, 'Scan catalogue QR',
          'Read the QR destination, download the catalogue, and archive the file', _scanQr),
      _vaultAction(Icons.link_outlined, 'Download from supplier link',
          'Download the supplied link now so it remains available after it expires', _downloadFromLink),
      _vaultAction(Icons.document_scanner_outlined, 'Photograph hard copy',
          'Archive a printed brochure page as supplier catalogue evidence', _captureHardCopy),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
      if (_message != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.primary))),
    ]),
  );

  Widget _vaultAction(IconData icon, String title, String subtitle,
      Future<void> Function() onTap) => Card(child: ListTile(
        leading: Icon(icon), title: Text(title), subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy || _supplier == null ? null : onTap,
      ));
}

class _CatalogueQrScanner extends StatefulWidget {
  const _CatalogueQrScanner();

  @override
  State<_CatalogueQrScanner> createState() => _CatalogueQrScannerState();
}

class _CatalogueQrScannerState extends State<_CatalogueQrScanner> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan catalogue QR code')),
    body: MobileScanner(
      onDetect: (capture) {
        if (_done) return;
        final value = capture.barcodes.firstOrNull?.rawValue?.trim();
        if (value == null || value.isEmpty) return;
        _done = true;
        Navigator.pop(context, value);
      },
    ),
  );
}
