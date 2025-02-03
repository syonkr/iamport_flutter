import 'dart:convert';
import 'dart:core';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:portone_flutter/model/certification_data.dart';
import 'package:portone_flutter/model/iamport_validation.dart';
import 'package:portone_flutter/model/url_data.dart';
import 'package:portone_flutter/widget/iamport_error.dart';
import 'package:portone_flutter/widget/iamport_webview.dart';
import 'package:iamport_webview_flutter/iamport_webview_flutter.dart';

import 'iamport_webview_web.dart';

class IamportCertification extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? initialChild;
  final String userCode;
  final CertificationData data;
  final callback;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final String? customUserAgent;

  IamportCertification({
    Key? key,
    this.appBar,
    this.initialChild,
    required this.userCode,
    required this.data,
    required this.callback,
    this.gestureRecognizers,
    this.customUserAgent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var redirectUrl = UrlData.redirectUrl;
    if (this.data.mRedirectUrl != null && this.data.mRedirectUrl!.isNotEmpty) {
      redirectUrl = this.data.mRedirectUrl!;
    }

    IamportValidation validation =
        IamportValidation.fromCertificationData(userCode, data, callback);
    if (validation.getIsValid()) {
      if (kIsWeb) {
        return IamportWebViewWeb(
          appBar: this.appBar,
          initialChild: this.initialChild,
          userCode: this.userCode,
          paymentData: this.data.toJson(),
          redirectUrl: redirectUrl,
          isCertification: true,
          useQueryData: (Map<String, String> data) {
            this.callback(data);
          },
          customPGAction: (data) {
            return null;
          },
          isPaymentOver: (String url) {
            return url.startsWith(redirectUrl);
          },
        );
      }
      return IamportWebView(
        type: ActionType.auth,
        appBar: this.appBar,
        initialChild: this.initialChild,
        gestureRecognizers: this.gestureRecognizers,
        customUserAgent: this.customUserAgent,
        executeJS: (WebViewController controller) {
          controller.evaluateJavascript('''
            IMP.init("${this.userCode}");
            IMP.certification(${jsonEncode(this.data.toJson())}, function(response) {
              const query = [];
              Object.keys(response).forEach(function(key) {
                query.push(key + "=" + response[key]);
              });
              location.href = "$redirectUrl" + "?" + query.join("&");
            });
          ''');
        },
        useQueryData: (Map<String, String> data) {
          this.callback(data);
        },
        isPaymentOver: (String url) {
          return url.startsWith(redirectUrl);
        },
        // 인증에는 customPGAction 수행할 필요 없음
        customPGAction: (WebViewController controller) {},
      );
    } else {
      return IamportError(ActionType.auth, validation.getErrorMessage());
    }
  }
}
