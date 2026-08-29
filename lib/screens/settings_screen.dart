import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(Icons.lock),
            title: Text('App lock'),
            subtitle: Text('Planned: PIN / biometrics security for supplier data'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.cloud_upload),
            title: Text('Backup'),
            subtitle: Text('Planned: cloud sync profile + restore by trip'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.delete_forever),
            title: Text('Delete data'),
            subtitle: Text('Planned: per-trip wipe, export-before-delete workflow'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.language),
            title: Text('Language'),
            subtitle: Text('Planned: English, Chinese, Hindi'),
          ),
        ),
      ],
    );
  }
}

