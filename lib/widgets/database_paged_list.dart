import 'dart:async';
import 'package:flutter/material.dart';
import '../data/record_page_service.dart';
import 'record_search.dart';

typedef RecordPageLoader = Future<RecordPage> Function(int offset, int limit, String query);

class DatabasePagedList extends StatefulWidget {
  const DatabasePagedList({super.key, required this.loader, required this.itemBuilder,
    required this.searchHint, this.pageSize = 25, this.emptyMessage = 'No records yet.',
    this.refreshToken = 0, this.shrinkWrap = false, this.groupLabel});
  final RecordPageLoader loader;
  final Widget Function(BuildContext, Map<String, Object?>) itemBuilder;
  final String searchHint;
  final String emptyMessage;
  final int pageSize;
  final int refreshToken;
  final bool shrinkWrap;
  final String Function(Map<String, Object?>)? groupLabel;
  @override
  State<DatabasePagedList> createState() => DatabasePagedListState();
}

class DatabasePagedListState extends State<DatabasePagedList>
    with AutomaticKeepAliveClientMixin<DatabasePagedList> {
  @override
  bool get wantKeepAlive => true;
  List<Map<String, Object?>> _rows = [];
  int _total = 0, _generation = 0;
  String _query = '';
  String? _error;
  bool _loading = true;
  Timer? _debounce;
  final _scroll = ScrollController();

  @override
  void initState() { super.initState(); _fetch(reset: true); }
  @override
  void didUpdateWidget(covariant DatabasePagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) refresh();
  }
  @override
  void dispose() { _debounce?.cancel(); _scroll.dispose(); super.dispose(); }

  Future<void> refresh() => _fetch(reset: true, retain: true);

  Future<void> _fetch({bool reset = false, bool retain = false}) async {
    final generation = ++_generation;
    final offset = reset ? 0 : _rows.length;
    final limit = retain && _rows.length > widget.pageSize ? _rows.length : widget.pageSize;
    setState(() { _loading = true; _error = null; if (reset && !retain) _rows = []; });
    try {
      final page = await widget.loader(offset, limit, _query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _rows = reset ? List.of(page.rows) : [..._rows, ...page.rows];
        _total = page.total; _loading = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() { _error = '$error'; _loading = false; });
    }
  }

  void _search(String value) {
    _debounce?.cancel(); ++_generation;
    setState(() { _query = value; _loading = true; _rows = []; _total = 0; _error = null; });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(reset: true));
  }

  Widget _footer() => Padding(padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[Text(_error!), TextButton(onPressed: () =>
        _fetch(reset: _rows.isEmpty), child: const Text('Retry'))],
      if (!_loading && _error == null && _rows.isEmpty)
        Text(_query.trim().isEmpty ? widget.emptyMessage : 'No matches. Clear or change your search.'),
      if (_rows.length < _total && _error == null)
        OutlinedButton.icon(onPressed: _loading ? null : () => _fetch(),
          icon: const Icon(Icons.expand_more), label: const Text('Load more')),
    ]));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = ListView.separated(controller: widget.shrinkWrap ? null : _scroll,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: 20), itemCount: _rows.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => index == _rows.length ? _footer()
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.groupLabel != null && (index == 0 ||
                widget.groupLabel!(_rows[index]) != widget.groupLabel!(_rows[index - 1])))
              Padding(padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(widget.groupLabel!(_rows[index]),
                  style: Theme.of(context).textTheme.titleSmall)),
            widget.itemBuilder(context, _rows[index]),
          ]));
    return Column(mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RecordSearchField(hint: widget.searchHint, onChanged: _search),
      Padding(padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(_loading && _rows.isEmpty ? 'Loading records...' : 'Showing ${_rows.length} of $_total')),
      widget.shrinkWrap ? list : Expanded(child: list),
    ]);
  }
}
