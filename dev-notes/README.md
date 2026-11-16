# 개발 노트

Photo Tidy를 만들면서 알아 두면 좋은 개발 지식을 정리한 곳입니다.
웹 프론트엔드(JavaScript, React)를 아는 사람 기준으로, 익숙한 개념에 빗대어 설명합니다.
각 글의 예시는 이 프로젝트의 실제 코드에서 가져왔습니다.

## 읽는 순서

| # | 글 | 한 줄 요약 |
| --- | --- | --- |
| 1 | [iOS 앱과 웹의 차이](01-ios-vs-web.md) | 앱이 만들어지고 실행되는 방식, 권한, 서명 |
| 2 | [JS 개발자를 위한 Swift](02-swift-for-js-devs.md) | 문법을 JS와 나란히 비교 |
| 3 | [React 개발자를 위한 SwiftUI](03-swiftui-for-react-devs.md) | 컴포넌트·상태·라우팅 대응표 |
| 4 | [비동기와 스레드](04-async-and-threads.md) | async/await, 화면 스레드, 작업 취소 |
| 5 | [애플 프레임워크](05-apple-frameworks.md) | 사진첩, 이미지 분석, 지도, 장소 이름 |
| 6 | [이 앱의 알고리즘](06-algorithms.md) | 비슷한 사진 묶기, 선명도, 거리 계산 |
| 7 | [프로젝트 구조](07-project-structure.md) | 패키지 분리, XcodeGen, 타깃 |
| 8 | [테스트](08-testing.md) | 로직 테스트, 화면 테스트, 테스트를 검증하는 법 |
| 9 | [Git과 GitHub](09-git-github.md) | 커밋 작성자와 푸시 계정, 강제 푸시 |
| 10 | [성능 감각](10-performance.md) | 데이터가 많아질 때 생기는 문제 |
| 11 | [데이터·알고리즘 용어 풀이](11-data-and-algorithm-terms.md) | 캐시, 증분 처리, 임계값, 시간 복잡도, union-find 등 아홉 가지를 자세히 |
| — | [용어 사전](glossary.md) | 자주 나오는 말 모음 |

급하면 1 → 3 → 4만 읽어도 코드를 따라갈 수 있습니다.

## 다른 문서와의 관계

- `README.md`(저장소 루트): 실행·테스트 방법
- `llm-wiki/`: 이 프로젝트가 **어떻게 만들어졌는지**(구조, 결정, 알려진 문제)
- `dev-notes/`(여기): 그걸 이해하는 데 필요한 **일반 개발 지식**
