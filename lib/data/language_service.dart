import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LanguageService {
  static const _key = 'app_language';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String> load() async => await _storage.read(key: _key) ?? 'en';

  Future<void> save(String language) =>
      _storage.write(key: _key, value: language);
}

class AppLanguage extends InheritedWidget {
  final String code;

  const AppLanguage({super.key, required this.code, required super.child});

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguage>()?.code ?? 'en';

  @override
  bool updateShouldNotify(AppLanguage oldWidget) => code != oldWidget.code;
}

String tr(BuildContext context, String key) {
  const values = {
    'en': {
      'dashboard': 'Dashboard',
      'captures': 'Captures',
      'capture': 'Capture',
      'shortlist': 'Shortlist',
      'followUps': 'Follow-Ups',
      'analytics': 'Analytics',
      'export': 'Export',
      'settings': 'Settings',
      'language': 'Language',
      'system': 'System',
      'english': 'English',
      'chinese': 'Chinese',
      'hindi': 'Hindi',
      'chooseLanguage': 'Choose language',
      'languageSaved': 'Language updated',
      'operations': 'Canton Fair Operations',
      'supplierCapture': 'Supplier Capture',
      'shortlistWorkspace': 'Shortlist Workspace',
      'followUpQueue': 'Follow-up Queue',
      'businessIntelligence': 'Business Intelligence',
      'exportHub': 'Export & Sharing Hub',
      'addTrip': 'Add Trip',
      'addSupplier': 'Add Supplier',
      'addProduct': 'Add Product',
      'addContact': 'Add Contact',
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'editSupplier': 'Edit Supplier',
      'filters': 'Filters',
      'shortlistOnly': 'Shortlist only',
      'addMeeting': 'Add Meeting / Follow-up',
      'addQuote': 'Add quote version',
      'attachments': 'Attachments',
      'scheduleVisit': 'Schedule supplier visit',
      'controls': 'Controls',
      'reports': 'Reports',
      'visitQueues': 'Visit queues',
    },
    'zh': {
      'dashboard': '仪表板',
      'captures': '采集',
      'capture': '采集',
      'shortlist': '短名单',
      'followUps': '跟进',
      'analytics': '分析',
      'export': '导出',
      'settings': '设置',
      'language': '语言',
      'system': '系统',
      'english': '英语',
      'chinese': '中文',
      'hindi': '印地语',
      'chooseLanguage': '选择语言',
      'languageSaved': '语言已更新',
      'operations': '广交会运营',
      'supplierCapture': '供应商采集',
      'shortlistWorkspace': '短名单工作区',
      'followUpQueue': '跟进队列',
      'businessIntelligence': '商业智能',
      'exportHub': '导出与共享中心',
      'addTrip': '添加行程',
      'addSupplier': '添加供应商',
      'addProduct': '添加产品',
      'addContact': '添加联系人',
      'save': '保存',
      'cancel': '取消',
      'delete': '删除',
      'editSupplier': '编辑供应商',
      'filters': '筛选',
      'shortlistOnly': '仅短名单',
      'addMeeting': '添加会议/跟进',
      'addQuote': '添加报价版本',
      'attachments': '附件',
      'scheduleVisit': '安排供应商拜访',
      'controls': '控制',
      'reports': '报告',
      'visitQueues': '拜访队列',
    },
    'hi': {
      'dashboard': 'डैशबोर्ड',
      'captures': 'कैप्चर',
      'capture': 'कैप्चर',
      'shortlist': 'शॉर्टलिस्ट',
      'followUps': 'फॉलो-अप',
      'analytics': 'विश्लेषण',
      'export': 'निर्यात',
      'settings': 'सेटिंग्स',
      'language': 'भाषा',
      'system': 'सिस्टम',
      'english': 'अंग्रेज़ी',
      'chinese': 'चीनी',
      'hindi': 'हिंदी',
      'chooseLanguage': 'भाषा चुनें',
      'languageSaved': 'भाषा अपडेट की गई',
      'operations': 'कैंटन फेयर संचालन',
      'supplierCapture': 'आपूर्तिकर्ता कैप्चर',
      'shortlistWorkspace': 'शॉर्टलिस्ट कार्यक्षेत्र',
      'followUpQueue': 'फॉलो-अप कतार',
      'businessIntelligence': 'बिज़नेस इंटेलिजेंस',
      'exportHub': 'निर्यात और साझा केंद्र',
      'addTrip': 'यात्रा जोड़ें',
      'addSupplier': 'आपूर्तिकर्ता जोड़ें',
      'addProduct': 'उत्पाद जोड़ें',
      'addContact': 'संपर्क जोड़ें',
      'save': 'सहेजें',
      'cancel': 'रद्द करें',
      'delete': 'हटाएँ',
      'editSupplier': 'आपूर्तिकर्ता संपादित करें',
      'filters': 'फ़िल्टर',
      'shortlistOnly': 'केवल शॉर्टलिस्ट',
      'addMeeting': 'बैठक / फॉलो-अप जोड़ें',
      'addQuote': 'कोटेशन संस्करण जोड़ें',
      'attachments': 'संलग्नक',
      'scheduleVisit': 'आपूर्तिकर्ता यात्रा शेड्यूल करें',
      'controls': 'नियंत्रण',
      'reports': 'रिपोर्ट',
      'visitQueues': 'यात्रा कतारें',
    },
  };
  return values[AppLanguage.of(context)]?[key] ?? values['en']![key] ?? key;
}
