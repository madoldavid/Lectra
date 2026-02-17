import '/flutter_flow/flutter_flow_util.dart';
import 'account_settings_page_widget.dart' show AccountSettingsPageWidget;
import 'package:flutter/material.dart';

class AccountSettingsPageModel extends FlutterFlowModel<AccountSettingsPageWidget> {

  final unfocusNode = FocusNode();

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    unfocusNode.dispose();
  }
}