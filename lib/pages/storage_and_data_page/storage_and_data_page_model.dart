import '/flutter_flow/flutter_flow_util.dart';
import 'storage_and_data_page_widget.dart' show StorageAndDataPageWidget;
import 'package:flutter/material.dart';

class StorageAndDataPageModel extends FlutterFlowModel<StorageAndDataPageWidget> {

  final unfocusNode = FocusNode();

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    unfocusNode.dispose();
  }
}