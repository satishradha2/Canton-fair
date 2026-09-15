/// Wire contract for the capability-gated additive field-work protocol.
class FieldWorkSyncContract {
  static const capabilityRpc = 'field_work_sync_version';
  static const version = 1;

  /// Parent-first order; deletions must use the reverse order.
  static const tables = <String, String>{
    'product_category': 'product_categories',
    'supplier_participation': 'supplier_participations',
    'exhibitor_booth': 'exhibitor_booths',
    'visit_plan': 'visit_plans',
    'visit_session': 'visit_sessions',
    'product_category_assignment': 'product_category_assignments',
  };

  static const relations = <String, Map<String, String>>{
    'supplier_participation': {
      'exhibitor_id': 'supplier',
      'trip_id': 'trip',
    },
    'exhibitor_booth': {'participation_id': 'supplier_participation'},
    'visit_plan': {'booth_id': 'exhibitor_booth'},
    'visit_session': {
      'participation_id': 'supplier_participation',
      'booth_id': 'exhibitor_booth',
      'plan_id': 'visit_plan',
    },
    'product_category_assignment': {
      'product_id': 'product',
      'category_id': 'product_category',
    },
  };

  static String primaryKey(String type) =>
      type == 'product_category_assignment' ? 'product_id' : 'id';

  static bool optionalRelation(String type, String column) =>
      type == 'visit_session' &&
      (column == 'booth_id' || column == 'plan_id');
}
