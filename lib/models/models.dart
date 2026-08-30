import 'dart:convert';

class Trip {
  final int? id;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final String city;
  final String notes;
  final String assigneeEmail;

  Trip({
    this.id,
    required this.name,
    this.startDate,
    this.endDate,
    required this.city,
    this.notes = '',
    this.assigneeEmail = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'start_date': startDate?.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'city': city,
        'notes': notes,
        'assignee_email': assigneeEmail,
      };

  factory Trip.fromMap(Map<String, dynamic> map) => Trip(
        id: map['id'] as int?,
        name: map['name'] as String,
        startDate: map['start_date'] != null
            ? DateTime.parse(map['start_date'])
            : null,
        endDate:
            map['end_date'] != null ? DateTime.parse(map['end_date']) : null,
        city: map['city'] as String,
        notes: map['notes'] as String? ?? '',
        assigneeEmail: map['assignee_email'] as String? ?? '',
      );
}

class Exhibitor {
  final int? id;
  final int tripId;
  final String name;
  final String booth;
  final String hall;
  final String category;
  final String country;
  final String contactCompanyNotes;
  final bool shortlisted;
  final int rating;
  final String tagsJson;
  final int qualityScore;
  final int responseSpeedScore;
  final int trustScore;
  final int moqFitScore;
  final int reliabilityScore;
  final DateTime? plannedVisitAt;
  final DateTime? visitedAt;

  Exhibitor({
    this.id,
    required this.tripId,
    required this.name,
    required this.booth,
    required this.hall,
    required this.category,
    required this.country,
    this.contactCompanyNotes = '',
    this.shortlisted = false,
    this.rating = 0,
    this.tagsJson = '[]',
    this.qualityScore = 0,
    this.responseSpeedScore = 0,
    this.trustScore = 0,
    this.moqFitScore = 0,
    this.reliabilityScore = 0,
    this.plannedVisitAt,
    this.visitedAt,
  });

  double get decisionScore =>
      (qualityScore +
          responseSpeedScore +
          trustScore +
          moqFitScore +
          reliabilityScore) *
      4.0;

  List<String> get tags {
    try {
      final list = (jsonDecode(tagsJson) as List?) ?? [];
      return list.whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'trip_id': tripId,
        'name': name,
        'booth': booth,
        'hall': hall,
        'category': category,
        'country': country,
        'notes': contactCompanyNotes,
        'shortlisted': shortlisted ? 1 : 0,
        'rating': rating,
        'tags_json': tagsJson,
        'quality_score': qualityScore,
        'response_speed_score': responseSpeedScore,
        'trust_score': trustScore,
        'moq_fit_score': moqFitScore,
        'reliability_score': reliabilityScore,
        'planned_visit_at': plannedVisitAt?.toIso8601String(),
        'visited_at': visitedAt?.toIso8601String(),
      };

  factory Exhibitor.fromMap(Map<String, dynamic> map) => Exhibitor(
        id: map['id'] as int?,
        tripId: map['trip_id'] as int,
        name: map['name'] as String,
        booth: map['booth'] as String,
        hall: map['hall'] as String,
        category: map['category'] as String,
        country: map['country'] as String,
        contactCompanyNotes: map['notes'] as String? ?? '',
        shortlisted: (map['shortlisted'] as int) == 1,
        rating: map['rating'] as int? ?? 0,
        tagsJson: map['tags_json'] as String? ?? '[]',
        qualityScore: map['quality_score'] as int? ?? 0,
        responseSpeedScore: map['response_speed_score'] as int? ?? 0,
        trustScore: map['trust_score'] as int? ?? 0,
        moqFitScore: map['moq_fit_score'] as int? ?? 0,
        reliabilityScore: map['reliability_score'] as int? ?? 0,
        plannedVisitAt: map['planned_visit_at'] != null
            ? DateTime.parse(map['planned_visit_at'] as String)
            : null,
        visitedAt: map['visited_at'] != null
            ? DateTime.parse(map['visited_at'] as String)
            : null,
      );
}

class Contact {
  final int? id;
  final int exhibitorId;
  final String name;
  final String designation;
  final String phone;
  final String email;
  final String whatsapp;
  final String wechat;

  Contact({
    this.id,
    required this.exhibitorId,
    required this.name,
    this.designation = '',
    this.phone = '',
    this.email = '',
    this.whatsapp = '',
    this.wechat = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'exhibitor_id': exhibitorId,
        'name': name,
        'designation': designation,
        'phone': phone,
        'email': email,
        'whatsapp': whatsapp,
        'wechat': wechat,
      };

  factory Contact.fromMap(Map<String, dynamic> map) => Contact(
        id: map['id'] as int?,
        exhibitorId: map['exhibitor_id'] as int,
        name: map['name'] as String,
        designation: map['designation'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        email: map['email'] as String? ?? '',
        whatsapp: map['whatsapp'] as String? ?? '',
        wechat: map['wechat'] as String? ?? '',
      );
}

class Product {
  final int? id;
  final int exhibitorId;
  final String name;
  final String modelCode;
  final String specs;
  final double? moq;
  final double? quotedPrice;
  final String priceCurrency;
  final String leadTime;
  final String paymentTerms;
  final bool shortlisted;
  final int rating;

  Product({
    this.id,
    required this.exhibitorId,
    required this.name,
    this.modelCode = '',
    this.specs = '',
    this.moq,
    this.quotedPrice,
    this.priceCurrency = 'USD',
    this.leadTime = '',
    this.paymentTerms = '',
    this.shortlisted = false,
    this.rating = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'exhibitor_id': exhibitorId,
        'name': name,
        'model_code': modelCode,
        'specs': specs,
        'moq': moq,
        'quoted_price': quotedPrice,
        'price_currency': priceCurrency,
        'lead_time': leadTime,
        'payment_terms': paymentTerms,
        'shortlisted': shortlisted ? 1 : 0,
        'rating': rating,
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as int?,
        exhibitorId: map['exhibitor_id'] as int,
        name: map['name'] as String,
        modelCode: map['model_code'] as String? ?? '',
        specs: map['specs'] as String? ?? '',
        moq: map['moq'] != null ? (map['moq'] as num).toDouble() : null,
        quotedPrice: map['quoted_price'] != null
            ? (map['quoted_price'] as num).toDouble()
            : null,
        priceCurrency: map['price_currency'] as String? ?? 'USD',
        leadTime: map['lead_time'] as String? ?? '',
        paymentTerms: map['payment_terms'] as String? ?? '',
        shortlisted: (map['shortlisted'] as int) == 1,
        rating: map['rating'] as int? ?? 0,
      );
}

class Meeting {
  final int? id;
  final int exhibitorId;
  final int? productId;
  final DateTime meetingDate;
  final DateTime? followUpDate;
  final String outcome;
  final String priority;
  final String notes;
  final String assigneeEmail;
  final bool completed;

  Meeting({
    this.id,
    required this.exhibitorId,
    this.productId,
    required this.meetingDate,
    this.followUpDate,
    this.outcome = 'Interested',
    this.priority = 'Medium',
    this.notes = '',
    this.assigneeEmail = '',
    this.completed = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'exhibitor_id': exhibitorId,
        'product_id': productId,
        'meeting_date': meetingDate.toIso8601String(),
        'follow_up_date': followUpDate?.toIso8601String(),
        'outcome': outcome,
        'priority': priority,
        'notes': notes,
        'assignee_email': assigneeEmail,
        'completed': completed ? 1 : 0,
      };

  factory Meeting.fromMap(Map<String, dynamic> map) => Meeting(
        id: map['id'] as int?,
        exhibitorId: map['exhibitor_id'] as int,
        productId: map['product_id'] as int?,
        meetingDate: DateTime.parse(map['meeting_date']),
        followUpDate: map['follow_up_date'] != null
            ? DateTime.parse(map['follow_up_date'])
            : null,
        outcome: map['outcome'] as String? ?? 'Interested',
        priority: map['priority'] as String? ?? 'Medium',
        notes: map['notes'] as String? ?? '',
        assigneeEmail: map['assignee_email'] as String? ?? '',
        completed: (map['completed'] as int) == 1,
      );
}

class Quote {
  final int? id;
  final int productId;
  final String label;
  final double? unitPrice;
  final String currency;
  final double? moq;
  final String note;
  final DateTime? validUntil;
  final bool isSampleQuote;

  Quote({
    this.id,
    required this.productId,
    required this.label,
    this.unitPrice,
    this.currency = 'USD',
    this.moq,
    this.note = '',
    this.validUntil,
    this.isSampleQuote = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'product_id': productId,
        'label': label,
        'unit_price': unitPrice,
        'currency': currency,
        'moq': moq,
        'note': note,
        'valid_until': validUntil?.toIso8601String(),
        'is_sample_quote': isSampleQuote ? 1 : 0,
      };

  factory Quote.fromMap(Map<String, dynamic> map) => Quote(
        id: map['id'] as int?,
        productId: map['product_id'] as int,
        label: map['label'] as String,
        unitPrice: map['unit_price'] != null
            ? (map['unit_price'] as num).toDouble()
            : null,
        currency: map['currency'] as String? ?? 'USD',
        moq: map['moq'] != null ? (map['moq'] as num).toDouble() : null,
        note: map['note'] as String? ?? '',
        validUntil: map['valid_until'] != null
            ? DateTime.parse(map['valid_until'])
            : null,
        isSampleQuote: (map['is_sample_quote'] as int) == 1,
      );
}

class Attachment {
  final int? id;
  final String ownerType;
  final int ownerId;
  final String kind;
  final String path;
  final String note;
  final DateTime createdAt;

  Attachment({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.kind,
    required this.path,
    required this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'owner_type': ownerType,
        'owner_id': ownerId,
        'kind': kind,
        'path': path,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };

  factory Attachment.fromMap(Map<String, dynamic> map) => Attachment(
        id: map['id'] as int?,
        ownerType: map['owner_type'] as String,
        ownerId: map['owner_id'] as int,
        kind: map['kind'] as String? ?? 'image',
        path: map['path'] as String,
        note: map['note'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at']),
      );
}

class SavedSupplierFilter {
  final int? id;
  final String name;
  final String query;
  final String country;
  final int minRating;
  final bool shortlistOnly;
  final String visitStatus;
  final double? minPrice;
  final double? maxPrice;
  final double? minMoq;
  final double? maxMoq;
  final bool expiringQuotesOnly;

  const SavedSupplierFilter({
    this.id,
    required this.name,
    this.query = '',
    this.country = '',
    this.minRating = 0,
    this.shortlistOnly = false,
    this.visitStatus = 'all',
    this.minPrice,
    this.maxPrice,
    this.minMoq,
    this.maxMoq,
    this.expiringQuotesOnly = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'query': query,
        'country': country,
        'min_rating': minRating,
        'shortlist_only': shortlistOnly ? 1 : 0,
        'visit_status': visitStatus,
        'min_price': minPrice,
        'max_price': maxPrice,
        'min_moq': minMoq,
        'max_moq': maxMoq,
        'expiring_quotes_only': expiringQuotesOnly ? 1 : 0,
      };

  factory SavedSupplierFilter.fromMap(Map<String, dynamic> map) =>
      SavedSupplierFilter(
        id: map['id'] as int?,
        name: map['name'] as String,
        query: map['query'] as String? ?? '',
        country: map['country'] as String? ?? '',
        minRating: map['min_rating'] as int? ?? 0,
        shortlistOnly: (map['shortlist_only'] as int? ?? 0) == 1,
        visitStatus: map['visit_status'] as String? ?? 'all',
        minPrice: map['min_price'] == null
            ? null
            : (map['min_price'] as num).toDouble(),
        maxPrice: map['max_price'] == null
            ? null
            : (map['max_price'] as num).toDouble(),
        minMoq:
            map['min_moq'] == null ? null : (map['min_moq'] as num).toDouble(),
        maxMoq:
            map['max_moq'] == null ? null : (map['max_moq'] as num).toDouble(),
        expiringQuotesOnly: (map['expiring_quotes_only'] as int? ?? 0) == 1,
      );
}
