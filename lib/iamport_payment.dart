import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:portone_flutter/model/iamport_validation.dart';
import 'package:portone_flutter/model/payment_data.dart';
import 'package:portone_flutter/model/url_data.dart';
import 'package:portone_flutter/widget/iamport_error.dart';
import 'package:portone_flutter/widget/iamport_webview.dart';
import 'package:iamport_webview_flutter/iamport_webview_flutter.dart';
import 'package:app_links/app_links.dart';

import 'iamport_webview_web.dart';

class IamportPayment extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? initialChild;
  final String userCode;
  final PaymentData data;
  final callback;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final _appLinks = AppLinks();

  IamportPayment({
    Key? key,
    this.appBar,
    this.initialChild,
    required this.userCode,
    required this.data,
    required this.callback,
    this.gestureRecognizers,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    IamportValidation validation =
        IamportValidation(this.userCode, this.data, this.callback);

    if (validation.getIsValid()) {
      var redirectUrl = UrlData.redirectUrl;
      if (this.data.mRedirectUrl != null &&
          this.data.mRedirectUrl!.isNotEmpty) {
        redirectUrl = this.data.mRedirectUrl!;
      }
      if (kIsWeb) {
        return IamportWebViewWeb(
          appBar: this.appBar,
          initialChild: this.initialChild,
          userCode: this.userCode,
          paymentData: this.data.toJson(),
          redirectUrl: redirectUrl,
          useQueryData: (Map<String, String> data) {
            this.callback(data);
          },
          customPGAction: (data) {
            return null;
          },
          isPaymentOver: (String url) {
            if (url.startsWith(redirectUrl)) {
              return true;
            }

            if (this.data.payMethod == 'trans') {
              /* [IOS] imp_uid와 merchant_uid값만 전달되기 때문에 결제 성공 또는 실패 구분할 수 없음 */
              String decodedUrl = Uri.decodeComponent(url);
              Uri parsedUrl = Uri.parse(decodedUrl);
              String scheme = parsedUrl.scheme;
              if (this.data.pg == 'html5_inicis') {
                Map<String, String> query = parsedUrl.queryParameters;
                if (query['m_redirect_url'] != null &&
                    scheme == this.data.appScheme.toLowerCase()) {
                  if (query['m_redirect_url']!.contains(redirectUrl)) {
                    return true;
                  }
                }
              }
            }

            return false;
          },
        );
      }
      return IamportWebView(
        type: ActionType.payment,
        appBar: this.appBar,
        initialChild: this.initialChild,
        gestureRecognizers: this.gestureRecognizers,
        executeJS: (WebViewController controller) {
          controller.evaluateJavascript('''
            IMP.init("${this.userCode}");
            IMP.request_pay(${jsonEncode(this.data.toJson())}, function(response) {
              const query = [];
              Object.keys(response).forEach(function(key) {
                query.push(key + "=" + response[key]);
              });
              location.href = "$redirectUrl" + "?" + query.join("&");
            });
          ''');
        },
        customPGAction: (WebViewController controller) {
          if (this.data.pg == 'smilepay') {
            // webview_flutter에서 iOS는 쿠키가 기본적으로 허용되어있는 것으로 추정
            if (!kIsWeb && Platform.isAndroid) {
              controller.setAcceptThirdPartyCookies(true);
            }
          }
          /* [v0.9.6] niceMobileV2: true 대비 코드 작성 */
          if (this.data.pg == 'nice' && this.data.payMethod == 'trans') {
            try {
              StreamSubscription sub =
                  _appLinks.uriLinkStream.listen((Uri? link) async {
                if (link != null) {
                  String decodedUrl = Uri.decodeComponent(link.toString());
                  Uri parsedUrl = Uri.parse(decodedUrl);
                  String scheme = parsedUrl.scheme;
                  if (scheme == data.appScheme.toLowerCase()) {
                    String queryToString = parsedUrl.query;
                    String? niceTransRedirectionUrl;
                    parsedUrl.queryParameters.forEach((key, value) {
                      if (key == 'callbackparam1') {
                        niceTransRedirectionUrl = value;
                      }
                    });
                    await controller.evaluateJavascript('''
                    location.href = "$niceTransRedirectionUrl?$queryToString";
                  ''');
                  }
                }
              });
              return sub;
            } on FormatException {}
          }
          return null;
        },
        useQueryData: (Map<String, String> data) {
          this.callback(data);
        },
        isPaymentOver: (String url) {
          if (url.startsWith(redirectUrl)) {
            return true;
          }

          if (this.data.payMethod == 'trans') {
            /* [IOS] imp_uid와 merchant_uid값만 전달되기 때문에 결제 성공 또는 실패 구분할 수 없음 */
            String decodedUrl = Uri.decodeComponent(url);
            Uri parsedUrl = Uri.parse(decodedUrl);
            String scheme = parsedUrl.scheme;
            if (this.data.pg == 'html5_inicis') {
              Map<String, String> query = parsedUrl.queryParameters;
              if (query['m_redirect_url'] != null &&
                  scheme == this.data.appScheme.toLowerCase()) {
                if (query['m_redirect_url']!.contains(redirectUrl)) {
                  return true;
                }
              }
            }
          }

          return false;
        },
      );
    } else {
      return IamportError(ActionType.payment, validation.getErrorMessage());
    }
  }
}
