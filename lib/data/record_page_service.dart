import 'database.dart';
import 'team_workspace_service.dart';

class RecordPage {
  const RecordPage(this.rows, this.total);
  final List<Map<String, Object?>> rows;
  final int total;
}

/// Count and fetch the same filtered set in one read transaction.
class RecordPageService {
  static String _json(String column, String path) =>
      "json_extract(CASE WHEN json_valid($column) THEN $column ELSE '{}' END, '$path')";

  static Future<RecordPage> _read({required String from, required String select,
    required String order, required List<String> searchColumns,
    required int offset, required int limit, String query = '',
    String where = '1=1', List<Object?> arguments = const []}) async {
    final workspace = TeamWorkspaceService();
    final scope = await workspace.scopeKey();
    final db = await TradeDatabase.instance.database;
    final args = <Object?>[...arguments];
    for (final word in query.trim().toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty)) {
      where += ' AND (${searchColumns.map((column) => "LOWER(COALESCE($column, '')) LIKE ? ESCAPE '\\'").join(' OR ')})';
      final escaped = word.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
      args.addAll(List.filled(searchColumns.length, '%$escaped%'));
    }
    final result = await db.transaction((txn) async {
      final count = await txn.rawQuery('SELECT COUNT(*) AS total FROM $from WHERE $where', args);
      final rows = await txn.rawQuery('SELECT $select FROM $from WHERE $where ORDER BY $order LIMIT ? OFFSET ?',
        [...args, limit, offset]);
      return RecordPage(rows, count.single['total'] as int);
    });
    if (scope != await workspace.scopeKey()) throw StateError('Workspace changed. Reopen this list.');
    return result;
  }

  static Future<RecordPage> companies(int offset, int limit, String query) => _read(
    from: 'exhibitors e', select: 'e.*, (SELECT COUNT(*) FROM contacts c WHERE c.exhibitor_id=e.id) AS contact_count', order: 'LOWER(e.name), e.id',
    offset: offset, limit: limit, query: query,
    searchColumns: ['e.name', 'e.country', 'e.category', 'e.field_capture_json',
      "(SELECT GROUP_CONCAT(c.name || ' ' || c.email || ' ' || c.phone, ' ') FROM contacts c WHERE c.exhibitor_id=e.id)"]);

  static Future<RecordPage> products(int company, int offset, int limit, String query,
      {String? visitKey}) => _read(
    from: 'products p', select: "p.*, (SELECT GROUP_CONCAT(c.name, ', ') FROM product_category_assignments a JOIN product_categories c ON c.id=a.category_id WHERE a.product_id=p.id) AS category",
    order: 'LOWER(p.name), p.id', where: 'p.exhibitor_id=?${visitKey == null ? '' : " AND EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(p.details_json) THEN p.details_json ELSE '{}' END, '\$.visit_keys') j WHERE j.value=?)"}',
    arguments: [company, if (visitKey != null) visitKey], offset: offset, limit: limit, query: query,
    searchColumns: ['p.name', 'p.model_code', 'p.specs', 'p.details_json',
      "(SELECT GROUP_CONCAT(c.name, ' ') FROM product_category_assignments a JOIN product_categories c ON c.id=a.category_id WHERE a.product_id=p.id)"]);

  static Future<RecordPage> shortlist(bool product, int offset, int limit, String query,
      {String? category}) => _read(
    from: product ? 'products p JOIN exhibitors e ON e.id=p.exhibitor_id' : 'exhibitors e',
    select: product ? 'p.*, e.name AS company_name' : 'e.*',
    order: product ? 'LOWER(p.name), p.id' : 'LOWER(e.name), e.id',
    where: '${product ? 'p.shortlisted=1' : 'e.shortlisted=1'}${category == null ? '' : product ? ' AND EXISTS (SELECT 1 FROM product_category_assignments a JOIN product_categories c ON c.id=a.category_id WHERE a.product_id=p.id AND c.name=?)' : " AND instr(LOWER(e.category), LOWER(?))>0"}',
    arguments: [if (category != null) category],
    searchColumns: [if (product) 'p.name', 'e.name',
      _json(product ? 'p.details_json' : 'e.field_capture_json', '\$.shortlist.reason'),
      _json(product ? 'p.details_json' : 'e.field_capture_json', '\$.shortlist.fair')],
    offset: offset, limit: limit, query: query);

  static Future<RecordPage> visits(bool history, int? company, int offset, int limit, String query,
      {String? phase}) => _read(
    from: 'meetings m JOIN exhibitors e ON e.id=m.exhibitor_id',
    select: 'm.*, e.name AS company_name',
    order: history ? 'm.meeting_date DESC, m.id DESC' : 'm.meeting_date, m.id',
    where: "${_json('m.commitments_json', '\$.format')}=? AND ${_json('m.commitments_json', '\$.status')} ${history ? 'IN' : 'NOT IN'} ('Completed','Cancelled')${phase == 'active' ? " AND ${_json('m.commitments_json', '\$.status')}='In progress'" : phase == 'upcoming' ? " AND ${_json('m.commitments_json', '\$.status')} IN ('Tentative','Confirmed')" : ''}${company == null ? '' : ' AND m.exhibitor_id=?'}",
    arguments: ['fair-expert-company-visit-v1', if (company != null) company],
    searchColumns: ['e.name', ...['contact_name', 'address', 'purpose', 'type', 'status']
      .map((key) => _json('m.commitments_json', '\$.$key'))],
    offset: offset, limit: limit, query: query);

  static Future<RecordPage> categories(int offset, int limit, String query) => _read(
    from: 'product_categories', select: '*', where: 'archived=0',
    order: 'LOWER(name), id', searchColumns: ['name'], offset: offset, limit: limit, query: query);

  static Future<RecordPage> fairs(int offset, int limit, String query) => _read(
    from: 'trips', select: '*', where: 'name<>?', arguments: ['Fair Expert contacts'],
    order: 'LOWER(name), id', searchColumns: ['name', 'city', 'notes'],
    offset: offset, limit: limit, query: query);

  static Future<RecordPage> halls(int offset, int limit, String query, {int? fairId}) {
    const marker = '\n\n[fair-expert-halls]';
    final suffix = "substr(t.notes, instr(t.notes, '$marker') + ${marker.length})";
    return _read(from: "trips t JOIN json_each(CASE WHEN instr(t.notes, '$marker') > 0 AND json_valid($suffix) THEN $suffix ELSE '[]' END) h",
      select: 't.id AS fair_id, t.name AS fair_name, h.value AS name',
      where: fairId == null ? '1=1' : 't.id=?', arguments: [if (fairId != null) fairId],
      order: 'LOWER(t.name), t.id, LOWER(h.value), h.key', searchColumns: ['t.name', 'h.value'],
      offset: offset, limit: limit, query: query);
  }
}
