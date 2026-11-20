# 모이챗 · MoyiChat

Kanana 1.5 2.1B Instruct(2505)를 기기에서 실행하는 한국어 AI 앱이다. Android와 iOS가 Flutter 화면과 llama.cpp 기반 추론 코드를 공유한다.

## 앱 사용

1. 시작 화면에서 **모델 다운로드**를 누르고 다운로드 안내에 동의한다. 약 1.52GB를 받는 동안 속도를 확인하고 일시 정지할 수 있다. 검증과 모델 로딩이 끝나면 채팅 화면이 열린다.
2. 메시지를 바로 입력하거나 **내용 요약**, **문장 다듬기**, **답장 초안**, **사진 분석**을 고른다.
3. **사진 분석**에서 미리보기를 확인하고 **이미지 추가하기**를 누른다. 메시지당 최대 10장을 첨부할 수 있다. 인식한 글자와 분류 후보는 모델에 참고 자료로 전달되며, 입력창에는 직접 쓴 질문과 첨부 썸네일만 표시된다. Android는 ML Kit, iOS는 Apple Vision을 사용한다.
4. **작업 메뉴**에서 대화를 만들거나 이름을 바꾸고, 저장된 메시지를 검색할 수 있다. 하위 작업은 상위 작업의 최근 대화를 참고한다. 대화는 상위·하위 두 단계까지 만들 수 있다.
5. 도우미 이름은 기본적으로 **모이챗**이다. “앞으로 너를 루나라고 부를게”처럼 대화로 바꾸면 다른 작업에서도 새 이름을 쓴다. “프로필 사진 바꿔줘”라고 보내거나 **사용자 설정 → 사진 바꾸기**에서 도우미 사진을 정할 수 있다.
6. **사용자 설정**에서 기기에 맞는 자동 처리량을 쓰거나 **작게 · 보통 · 많음**을 직접 고른다. 사진 OCR과 분류 후보도 입력 토큰으로 계산된다. 위험 요청의 일부는 로컬 규칙으로 처리하고, 모델에는 사진과 상위 대화를 참고 자료로 다루는 안전 지침을 적용한다.

사진 분석은 Kanana 파일을 받기 전에도 쓸 수 있다. Kanana는 이미지에서 나온 텍스트와 분류 후보를 받아 설명을 만든다. 모델을 받은 뒤에는 비행기 모드에서도 로컬 사진 분석과 채팅이 가능하도록 구성했다.

## 개발 및 빌드

### 브라우저에서 빠르게 테스트

Chrome에서 앱을 띄우고 Dart 파일을 수정한 뒤 터미널에서 `r`을 누르면 화면에 반영된다.

```sh
flutter run -d chrome
```

웹 미리보기는 실제 모바일 화면을 공유한다. **샘플 다운로드**로 동의, 속도 표시, 일시 정지·이어받기를 확인한다. 샘플 이미지나 컴퓨터의 이미지를 첨부할 수 있다. 작업과 도우미 이름은 현재 브라우저에 저장된다. 다운로드 화면을 다시 보려면 앱 정보에서 **웹 다운로드 다시 테스트**를 누른다. 실제 Kanana 추론, 기기 사진 인식, 광고는 모바일 빌드에서 테스트한다.

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
