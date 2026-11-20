# 모이챗 · MoyiChat

Kanana 1.5 2.1B Instruct(2505)를 기기에서 실행하는 한국어 AI 앱이다. Android와 iOS가 Flutter 화면과 llama.cpp 기반 추론 코드를 공유한다.

## 앱 사용

1. 앱에서 **모델 다운로드**를 눌러 4비트 Kanana 파일 약 1.52 GB를 받는다. 다운로드 중 **일시 정지**할 수 있으며 앱을 다시 열어도 파일을 이어받는다. 파일 검증이 끝나면 모델이 자동으로 열린다.
2. 메시지를 바로 입력하거나 **내용 요약**, **문장 다듬기**, **답장 초안**, **사진 분석**을 고른다.
3. **사진 분석**에서 사진을 선택하면 기기에서 글자와 분류 후보를 읽는다. 결과를 확인하거나 수정해 입력창에 추가한 뒤 질문과 함께 보낸다. Android는 앱에 포함된 ML Kit 모델, iOS는 Apple Vision을 사용한다. 분류 결과에는 물체나 장면의 후보가 포함될 수 있으며, 물체의 위치나 개수는 제공하지 않는다.
4. 한 개의 현재 대화를 기기에 저장한다. 상단의 **새 작업** 버튼에서 현재 기록을 지우고 다시 시작할 수 있다.

사진 분석은 Kanana 파일을 받기 전에도 쓸 수 있다. Kanana는 이미지에서 나온 텍스트와 분류 후보를 받아 설명을 만든다. 모델을 받은 뒤에는 비행기 모드에서도 로컬 사진 분석과 채팅이 가능하도록 구성했다.

## 개발 및 빌드

### 브라우저에서 빠르게 테스트

Chrome에서 앱을 띄우고 Dart 파일을 수정한 뒤 터미널에서 `r`을 누르면 화면에 반영된다.

```sh
flutter run -d chrome
```

웹 미리보기는 실제 모바일 화면을 공유한다. **샘플 다운로드**로 일시 정지와 이어받기를 확인한 뒤, 작업 카드와 채팅을 테스트할 수 있다. **사진 분석**은 편집 가능한 샘플 결과를 연다. 대화는 페이지를 새로고침하면 초기화된다. 실제 Kanana 추론, 기기 사진 인식, 광고는 모바일 빌드에서 테스트한다.

정적 웹 빌드는 `flutter build web --no-web-resources-cdn`으로 만들고 `build/web`을 로컬 HTTP 서버로 연다. GitHub Actions의 **MoyiChat web preview**에서도 같은 웹 빌드를 받을 수 있다.

### Android와 iOS

Flutter 3.50.1에서 작업했다. Android 빌드에는 Android SDK 36과 JDK가 필요하다. iOS에는 macOS와 Xcode가 필요하며, 프로젝트의 최소 배포 대상은 iOS 16.4다. iOS의 llama.cpp XCFramework는 Swift Package Manager로 연결한다.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Apple 실기기용 빌드는 Mac에서 Runner에 서명 팀을 설정한 뒤 실행한다.

```sh
flutter build ios
```

출시용 빌드에는 자체 번들 식별자와 스토어 배포 서명이 필요하다. Android 프로젝트의 기본 release 설정은 개발 편의를 위해 디버그 키를 사용한다.

## 온라인 광고

디버그 빌드는 연결이 있을 때만 Google AdMob 테스트 배너를 표시한다. 연결이 끊기면 배너를 제거하며 모델 추론과 사진 분석에는 영향이 없다. 광고 요청은 대화, 사진, 사진 분석 결과를 사용하지 않는다.

실제 광고는 배너 ID를 지정한 출시용 빌드에서만 활성화된다.

- Android는 빌드 환경 변수 `MOYI_ADMOB_ANDROID_APP_ID`와 빌드 옵션 `--dart-define=MOYI_ADMOB_ANDROID_BANNER_ID=...`를 설정한다.
- iOS는 [AdMob.xcconfig](ios/Flutter/AdMob.xcconfig)의 `MOYI_ADMOB_IOS_APP_ID`와 빌드 옵션 `--dart-define=MOYI_ADMOB_IOS_BANNER_ID=...`를 설정한다.

AdMob에서 동의 메시지를 설정하면 앱은 UMP에서 광고 요청 가능 여부를 확인한 뒤 비개인화 배너를 요청한다. UMP가 요구하는 지역에서는 앱 정보 화면에 광고 개인정보 설정을 표시한다.

## Mac 없이 TestFlight 빌드

1. Codemagic에서 이 저장소를 연결한다. **MoyiChat iOS build check**로 iOS 컴파일부터 확인할 수 있다.
2. Apple Developer에서 `com.moyichat.moyichat` 번들 ID를 등록하고 App Store Connect에서 그 ID로 iOS 앱을 만든다.
3. Codemagic 팀 설정에서 App Store Connect API 키를 **MoyiChat App Store Connect**라는 이름으로 연결한다. iOS 코드 서명 설정에서 이 앱의 App Store 배포 인증서와 프로비저닝 프로파일을 준비한다.
4. **MoyiChat TestFlight**를 실행한다. 빌드에 성공하면 서명된 IPA가 App Store Connect에 업로드된다. Apple 처리가 끝나면 TestFlight에서 내부 테스트 그룹에 빌드를 추가한다.

## 모델 배포

앱 설치 파일에 Kanana 가중치는 포함하지 않는다. 앱에서 첫 다운로드를 요청할 때 고정된 Hugging Face 리비전에서 파일을 받아 크기와 SHA-256을 검증한다. 사진과 대화 메시지는 모델 다운로드 요청에 포함되지 않는다.

원본은 Apache 2.0으로 배포된 [카카오 Kanana 1.5 2.1B Instruct(2505)](https://huggingface.co/kakaocorp/kanana-1.5-2.1b-instruct-2505)다. 다운로드 파일은 [커뮤니티 Q4_K_M GGUF 변환본](https://huggingface.co/TaeyoungLeeJack/kanana-1.5-2.1b-instruct-2505-Q4_K_M-GGUF/tree/9a6c4bf9e13fea91c3100a891e7312dd9911f098)이다. 출처, 변경 고지, 라이선스 전문은 앱 정보의 라이선스 화면에서 확인할 수 있다.
