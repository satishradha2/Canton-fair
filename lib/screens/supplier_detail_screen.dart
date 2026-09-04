import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/database.dart';
import '../data/reminder_service.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/enterprise_widgets.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Exhibitor supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  final _db = TradeDatabase.instance;
  late String _decision;
  late Future<List<Contact>> _contacts;
  late Future<List<Product>> _products;
  late Future<List<Meeting>> _meetings;
  late Future<List<Attachment>> _files;

  @override
  void initState() {
    super.initState();
    _decision = widget.supplier.decision;
    _reload();
  }

  Future<void> _setDecision(String decision) async {
    var reason = '';
    if (decision == 'Reject') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Why reject this supplier?'),
              content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Reason')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Save')),
              ],
            ),
          ) ??
          '';
      controller.dispose();
      if (reason.isEmpty) return;
    }
    await _db.update('exhibitors', widget.supplier.id!, {
      'decision': decision,
      'decision_reason': reason,
      'shortlisted': decision == 'Shortlist' ? 1 : 0,
    });
    if (mounted) setState(() => _decision = decision);
  }

  void _reload() {
    final id = widget.supplier.id!;
    _contacts = _db.getContacts(id);
    _products = _db.getProducts(id);
    _meetings = _db.getMeetings(exhibitorId: id);
    _files = _db.getAttachments('exhibitor', id);
  }

  Future<void> _shareSummary() async {
    final supplier = widget.supplier;
    final products = await _products;
    final lines = [
      supplier.name,
      if (supplier.booth.isNotEmpty) 'Booth: ${supplier.booth}',
      if (supplier.hall.isNotEmpty) 'Hall: ${supplier.hall}',
      if (supplier.category.isNotEmpty) 'Category: ${supplier.category}',
      if (supplier.country.isNotEmpty) 'Country: ${supplier.country}',
      'Status: ${supplier.visitedAt == null ? 'Need to visit' : 'Visited'}',
      'Rating: ${supplier.rating}/5',
      if (products.isNotEmpty)
        'Products: ${products.map((item) => item.name).join(', ')}',
      if (supplier.contactCompanyNotes.isNotEmpty)
        'Notes: ${supplier.contactCompanyNotes}',
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  Future<void> _openPhone(String phone, {bool whatsapp = false}) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = whatsapp
        ? Uri.parse('https://wa.me/${clean.replaceFirst('+', '')}')
        : Uri.parse('tel:$clean');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $phone')),
      );
    }
  }

  Future<void> _complete(Meeting meeting) async {
    await _db.update('meetings', meeting.id!, {'completed': 1});
    await ReminderService.cancel(meeting.id!);
    if (mounted) setState(_reload);
  }

  Widget _empty(String title, String message, IconData icon) => EmptyState(
        title: title,
        message: message,
        icon: icon,
      );

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(supplier.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Share supplier summary',
              onPressed: _shareSummary,
              icon: const Icon(Icons.ios_share_outlined),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Contacts'),
              Tab(text: 'Products'),
              Tab(text: 'Meetings'),
              Tab(text: 'Files'),
              Tab(text: 'Scorecard'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _overview(supplier),
            _contactsTab(),
            _productsTab(),
            _meetingsTab(),
            _filesTab(),
            _scorecard(supplier),
          ],
        ),
      ),
    );
  }

  Widget _overview(Exhibitor supplier) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(
                  label: supplier.booth.isEmpty
                      ? 'Booth not recorded'
                      : 'Booth ${supplier.booth}',
                  icon: Icons.place),
              if (supplier.hall.isNotEmpty)
                InfoChip(
                    label: supplier.hall,
                    icon: Icons.location_city,
                    color: AppColors.teal),
              if (supplier.shortlisted)
                const InfoChip(
                    label: 'Shortlisted',
                    icon: Icons.star,
                    color: Color(0xFF2F855A)),
              InfoChip(
                  label:
                      supplier.visitedAt == null ? 'Need to visit' : 'Visited',
                  icon: supplier.visitedAt == null
                      ? Icons.route_outlined
                      : Icons.task_alt,
                  color: supplier.visitedAt == null
                      ? AppColors.amber
                      : AppColors.teal),
              InfoChip(
                label: _decision,
                icon: _decision == 'Shortlist'
                    ? Icons.star
                    : _decision == 'Reject'
                        ? Icons.block_outlined
                        : Icons.help_outline,
                color: _decision == 'Shortlist'
                    ? const Color(0xFF2F855A)
                    : _decision == 'Reject'
                        ? AppColors.danger
                        : AppColors.amber,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionPanel(
            title: 'Supplier decision',
            subtitle:
                'Make a sourcing decision while the conversation is fresh.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                    label: const Text('Shortlist'),
                    selected: _decision == 'Shortlist',
                    onSelected: (_) => _setDecision('Shortlist')),
                ChoiceChip(
                    label: const Text('Maybe'),
                    selected: _decision == 'Maybe',
                    onSelected: (_) => _setDecision('Maybe')),
                ChoiceChip(
                    label: const Text('Reject'),
                    selected: _decision == 'Reject',
                    onSelected: (_) => _setDecision('Reject')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionPanel(
            title: 'Supplier notes',
            child: Text(supplier.contactCompanyNotes.isEmpty
                ? 'No supplier notes recorded yet.'
                : supplier.contactCompanyNotes),
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (tabContext) => SectionPanel(
              title: 'Quick actions',
              subtitle:
                  'Use the Contacts tab to call or message a specific person.',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                      onPressed: _shareSummary,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share summary')),
                  OutlinedButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(tabContext).animateTo(3),
                      icon: const Icon(Icons.event_note_outlined),
                      label: const Text('View tasks')),
                  OutlinedButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(tabContext).animateTo(4),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('View files')),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _contactsTab() => FutureBuilder<List<Contact>>(
        future: _contacts,
        builder: (context, snapshot) {
          final contacts = snapshot.data ?? const <Contact>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (contacts.isEmpty) {
            return _empty(
                'No contacts',
                'Add a contact from the supplier capture screen.',
                Icons.person_add_alt_1_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: contacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return Card(
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(
                      contact.name.isEmpty ? 'Unnamed contact' : contact.name),
                  subtitle: Text([
                    contact.designation,
                    contact.phone,
                    contact.email
                  ].where((item) => item.isNotEmpty).join('\n')),
                  isThreeLine: contact.designation.isNotEmpty &&
                      contact.phone.isNotEmpty,
                  trailing: Wrap(
                    children: [
                      if (contact.phone.isNotEmpty)
                        IconButton(
                            tooltip: 'Call',
                            onPressed: () => _openPhone(contact.phone),
                            icon: const Icon(Icons.call_outlined)),
                      if (contact.whatsapp.isNotEmpty ||
                          contact.phone.isNotEmpty)
                        IconButton(
                            tooltip: 'WhatsApp',
                            onPressed: () => _openPhone(
                                contact.whatsapp.isEmpty
                                    ? contact.phone
                                    : contact.whatsapp,
                                whatsapp: true),
                            icon: const Icon(Icons.chat_outlined)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

  Widget _productsTab() => FutureBuilder<List<Product>>(
        future: _products,
        builder: (context, snapshot) {
          final products = snapshot.data ?? const <Product>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (products.isEmpty) {
            return _empty(
                'No products',
                'Add products from the supplier capture screen.',
                Icons.inventory_2_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final product = products[index];
              return Card(
                  child: ListTile(
                title: Text(product.name),
                subtitle: Text(
                    'MOQ ${product.moq ?? '-'} | ${product.quotedPrice == null ? 'No quote' : '${product.quotedPrice} ${product.priceCurrency}'} | ${product.leadTime.isEmpty ? 'No lead time' : product.leadTime}'),
                trailing: product.shortlisted
                    ? const Icon(Icons.star, color: AppColors.amber)
                    : null,
              ));
            },
          );
        },
      );

  Widget _meetingsTab() => FutureBuilder<List<Meeting>>(
        future: _meetings,
        builder: (context, snapshot) {
          final meetings = snapshot.data ?? const <Meeting>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (meetings.isEmpty) {
            return _empty(
                'No follow-ups',
                'Create a follow-up from the supplier capture screen.',
                Icons.event_note_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: meetings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final meeting = meetings[index];
              return Card(
                  child: ListTile(
                leading: Icon(
                    meeting.completed ? Icons.task_alt : Icons.schedule,
                    color:
                        meeting.completed ? AppColors.teal : AppColors.amber),
                title: Text(meeting.outcome),
                subtitle: Text(
                    '${meeting.priority} priority${meeting.assigneeEmail.isEmpty ? '' : ' | ${meeting.assigneeEmail}'}${meeting.followUpDate == null ? '' : '\nDue ${meeting.followUpDate!.toLocal()}'}'),
                isThreeLine: meeting.followUpDate != null,
                trailing: meeting.completed
                    ? null
                    : IconButton(
                        tooltip: 'Mark complete',
                        onPressed: () => _complete(meeting),
                        icon: const Icon(Icons.check_circle_outline)),
              ));
            },
          );
        },
      );

  Widget _filesTab() => FutureBuilder<List<Attachment>>(
        future: _files,
        builder: (context, snapshot) {
          final files = snapshot.data ?? const <Attachment>[];
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (files.isEmpty) {
            return _empty(
                'No files',
                'Add a photo or document from the supplier capture screen.',
                Icons.attach_file_outlined);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: files.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final file = files[index];
              return Card(
                  child: ListTile(
                leading: Icon(file.kind == 'photo'
                    ? Icons.photo_outlined
                    : Icons.attach_file_outlined),
                title: Text(file.note.isEmpty ? file.kind : file.note),
                subtitle: Text(file.path,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ));
            },
          );
        },
      );

  Widget _scorecard(Exhibitor supplier) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionPanel(
            title: 'Supplier scorecard',
            subtitle: 'Scores recorded during supplier review.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InfoChip(
                    label: 'Rating ${supplier.rating}/5',
                    icon: Icons.star,
                    color: AppColors.amber),
                InfoChip(
                    label: 'Quality ${supplier.qualityScore}',
                    icon: Icons.verified_outlined),
                InfoChip(
                    label: 'Response ${supplier.responseSpeedScore}',
                    icon: Icons.speed_outlined,
                    color: AppColors.teal),
                InfoChip(
                    label: 'Trust ${supplier.trustScore}',
                    icon: Icons.handshake_outlined,
                    color: const Color(0xFF6B4E9B)),
                InfoChip(
                    label: 'MOQ fit ${supplier.moqFitScore}',
                    icon: Icons.inventory_2_outlined),
                InfoChip(
                    label: 'Reliability ${supplier.reliabilityScore}',
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF2F855A)),
              ],
            ),
          ),
        ],
      );
}
