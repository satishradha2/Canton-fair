import 'package:flutter/material.dart';
import '../data/approval_policy.dart';
import '../data/cloud_sync_service.dart';
import '../data/phone_cleanup_plan.dart';
import '../data/phone_cleanup_service.dart';
import '../data/team_workspace_service.dart';

class PhoneCleanupScreen extends StatefulWidget {
  const PhoneCleanupScreen({super.key});
  @override
  State<PhoneCleanupScreen> createState() => _PhoneCleanupScreenState();
}

class _PhoneCleanupScreenState extends State<PhoneCleanupScreen> {
  final _cloud = CloudSyncService();
  final _service = PhoneCleanupService();
  PhoneCleanupPlan? _plan;
  List<Map<String, dynamic>> _mine = [];
  List<Map<String, dynamic>> _requests = [];
  bool _busy = false;
  bool _admin = false;
  bool _paused = false;
  String? _message;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try { await action(); }
    catch (error) {
      if (mounted) setState(() => _message = 'Operation not completed: $error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _load() async {
    final role = await ApprovalPolicy.currentRole();
    final scope = await TeamWorkspaceService().scopeKey();
    final paused = await PhoneCleanupService.paused(scope);
    final mine = await _service.requests();
    final requests = role == 'admin' ? await _service.requests(admin: true) : <Map<String, dynamic>>[];
    if (mounted) {
      setState(() {
      _admin = role == 'admin'; _paused = paused;
      _mine = mine.map((row) => Map<String, dynamic>.from(row)).toList();
      _requests = requests.map((row) => Map<String, dynamic>.from(row)).toList();
      });
    }
  }

  Future<void> _refresh() => _run(_load);

  Future<bool> _confirm(String title, String description) async =>
    await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: Text(description), actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
      ])) ?? false;

  Future<String?> _reason(String title) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: TextField(controller: controller, maxLength: 1000,
        maxLines: 3, decoration: const InputDecoration(labelText: 'Reason / review note')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
        }, child: const Text('Continue'))]));
    // The dialog route may still be animating out; keep its controller alive until then.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return value;
  }

  Future<void> _check() => _run(() async {
    final plan = await _cloud.inspectPhoneCleanup();
    if (mounted) setState(() => _plan = plan);
  });

  Future<void> _clear({String? approvalId}) async {
    final plan = _plan;
    if (plan == null) return;
    final confirmed = await _confirm('Clear phone copies only?', approvalId == null
      ? 'Only verified cloud-backed copies will be removed from this phone. Cloud data and login remain unchanged. Sync will pause until you restore cloud copies.'
      : 'This removes the approved workspace snapshot from this phone, including unsynced records and drafts. Unsynced information may be permanently lost. Cloud data, login accounts, roles and team access are NOT deleted.');
    if (!confirmed || !mounted) return;
    await _run(() async {
      final result = await _cloud.clearPhoneCopies(plan, approvalId: approvalId);
      if (mounted) {
        setState(() {
        _plan = null; _paused = true;
        _message = 'Cleared ${result.records} phone records and ${result.files} files. Cloud data was not deleted. ${result.warnings.join(' ')}';
        });
      }
      await _load();
    });
  }

  Future<void> _request() async {
    final plan = _plan;
    if (plan == null) return;
    final reason = await _reason('Ask admin to clear unsynced phone data');
    if (reason == null || !mounted) return;
    await _run(() async {
      await _service.request(plan, reason);
      await _load();
      if (mounted) setState(() => _message = 'Request sent. An administrator can review it in Sync center > Phone storage. Approval does not automatically clear your phone.');
    });
  }

  Future<void> _review(Map<String, dynamic> request, bool approve) async {
    final note = await _reason(approve ? 'Approve phone-only cleanup' : 'Reject cleanup request');
    if (note == null || !mounted) return;
    await _run(() async {
      await _service.decide(request['id'].toString(), approve, note);
      await _load();
    });
  }

  Future<void> _restore() async {
    if (!await _confirm('Restore cloud copies?', 'Download the selected team workspace again and resume sync? Cloud records remain unchanged. Existing retained phone edits will use normal conflict handling.')) return;
    if (!mounted) return;
    await _run(() async {
      final scope = await TeamWorkspaceService().scopeKey();
      await PhoneCleanupService.setPaused(scope, false);
      try { await _cloud.syncTeamWorkspace(); }
      catch (_) { await PhoneCleanupService.setPaused(scope, true); rethrow; }
      await _load();
      if (mounted) setState(() => _message = 'Cloud copies restored. Sync resumed.');
    });
  }

  Widget _requestCard(Map<String, dynamic> row, {bool review = false}) {
    final status = row['status'].toString();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(review ? row['requested_email'].toString() : 'This phone', style: Theme.of(context).textTheme.titleMedium),
        Text('Status: $status'), Text(row['reason']?.toString() ?? ''),
        Text('Requested: ${row['created_at']}'),
        if ((row['review_note']?.toString() ?? '').isNotEmpty) Text('Admin: ${row['review_note']}'),
        if (review && status == 'pending') Wrap(spacing: 8, children: [
          FilledButton(onPressed: _busy ? null : () => _review(row, true), child: const Text('Approve phone cleanup')),
          OutlinedButton(onPressed: _busy ? null : () => _review(row, false), child: const Text('Reject')),
        ]),
        if (!review && status == 'approved') FilledButton(
          onPressed: _busy || _plan == null || _plan!.manifestHash != row['manifest_hash'] ? null
            : () => _clear(approvalId: row['id'].toString()), child: const Text('Clear approved phone snapshot')),
        if (!review && status == 'approved') const Text('Check cloud copies first. Changed phone data needs a new request. Approval expires after 7 days.'),
      ])));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Phone storage'), actions: [
      IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh approvals'),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_busy) const LinearProgressIndicator(),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Clear this phone, not the cloud', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Applies only to the selected team workspace on this phone. Login accounts, roles, team access and security settings are preserved. Other member phones must use this option separately.'),
          const SizedBox(height: 8),
          const Text('Verified cloud copies: no approval needed. Unsynced records, files and drafts: administrator approval required. Dependent records are retained together for safety.'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _busy ? null : _check, icon: const Icon(Icons.cloud_done_outlined), label: const Text('Check cloud copies')),
        ]))),
      if (_message != null) Padding(padding: const EdgeInsets.all(12), child: SelectableText(_message!)),
      if (_plan case final plan?) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${plan.entries.length} saved records / ${plan.files.length} phone files'),
          Text('${plan.verifiedCount} safe to clear now'),
          Text('${plan.protectedCount} protected records / ${plan.localOnlyCount} local-only items'),
          if (plan.localOnlyCount > 0) const Text('Local drafts/history are present. Automatic cleanup is conservatively blocked to avoid breaking their references. Sync or request admin approval.'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _busy || plan.verifiedCount == 0 ? null : () => _clear(), child: const Text('Clear verified phone copies')),
          OutlinedButton(onPressed: _busy ? null : _request, child: const Text('Request admin approval for full phone cleanup')),
        ]))),
      if (_paused) Card(child: ListTile(title: const Text('Sync paused on this phone'),
        subtitle: const Text('Cloud copies stay available to the team. Restore them when you want to work on this phone again.'),
        trailing: const Icon(Icons.cloud_download_outlined), onTap: _busy ? null : _restore)),
      const SizedBox(height: 16), Text('My phone requests', style: Theme.of(context).textTheme.titleLarge),
      if (_mine.isEmpty) const Text('No requests for this phone.'),
      ..._mine.map((row) => _requestCard(row)),
      if (_admin) ...[
        const SizedBox(height: 16), Text('Administrator review', style: Theme.of(context).textTheme.titleLarge),
        const Text('Review requests from all team phones. Approval permits only the recorded phone snapshot; it never deletes cloud business data.'),
        if (_requests.isEmpty) const Text('No team requests.'),
        ..._requests.map((row) => _requestCard(row, review: true)),
      ],
      const SizedBox(height: 16),
      const Text('Requires the phone-cleanup approval migration on Supabase. If approval services are unavailable, cleanup is blocked. Personal-workspace data and legacy unscoped drafts are not cleared here.'),
    ]),
  );
}
