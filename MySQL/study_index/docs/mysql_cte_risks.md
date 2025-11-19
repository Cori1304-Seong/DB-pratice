# MySQL에서 CTE가 위험한 이유 정리

## 0. 요약

- **주제**  
  MySQL 8.x 환경에서 `WITH [RECURSIVE]` CTE 사용 시 발생하는 제약과 위험 요소 정리

- **핵심 포인트**

  - CTE가 항상 materialized view처럼 동작하지 않음
  - INSERT/UPDATE/DELETE + CTE 조합 시 `Can't reopen table` 류 오류 가능
  - CLI/스크립트 환경에서 문장 경계·실행 단위에 민감

- **실무 결론**  
  복잡한 대량 데이터 생성/변환 작업에는 CTE보다 **TEMP TABLE / 헬퍼 테이블 / 단순 SELECT** 패턴 우선 고려

---

## 1. MySQL CTE 동작 특성

### 1-1. CTE 기본 개념

- `WITH [RECURSIVE] 이름 AS (서브쿼리)` 형태로 정의되는 임시 쿼리 블록
- 한 문장 안에서 여러 번 참조 가능
- 이론적으로는 "이름 있는 서브쿼리" 또는 "일시적 뷰" 역할

### 1-2. MySQL vs PostgreSQL CTE 동작 차이 (개괄)

- PostgreSQL
  - CTE를 기본적으로 materialized (중간 결과 저장) 하는 경향
  - 동일 CTE 여러 번 참조 시, 캐시된 결과 재사용
- MySQL
  - CTE를 반드시 materialize하지 않음
  - 옵티마이저가 필요 시 CTE를 인라인/재계산/재오픈할 수 있는 구조

→ 결과: CTE를 "한 번 계산해 놓고 안전하게 계속 쓰는 객체"라고 가정하면 위험

---

## 2. 주요 위험 1 — Can't reopen table 오류

### 2-1. 증상

- 에러 메시지
  - `ERROR 1137 (HY000): Can't reopen table: 'XYZ'`
- 상황 예시
  - 재귀 CTE 또는 CTE 기반 숫자 생성 후 `INSERT ... SELECT ... FROM CTE` 조합
  - CTE를 두 개 이상의 레벨에서 동시에 참조하는 구조

### 2-2. 원인

- MySQL이 CTE를 내부적으로 테이블/뷰처럼 관리하면서
  - 한 문장 안에서 동일 CTE를 두 번 오픈하려 할 때 충돌
- INSERT 대상 + SELECT 소스가 서로 얽혀 있는 경우
  - CTE가 INSERT와 SELECT 양쪽에서 동시에 필요
  - MySQL 엔진이 CTE를 다시 열지 못해 `Can't reopen table` 발생

### 2-3. 실무 영향

- CTE를 데이터 생성/변환 파이프라인에 활용할 때 불안정
- 특히 재귀 CTE + 대량 데이터 조합에서 빈번한 문제

---

## 3. 주요 위험 2 — 재귀 깊이 및 성능 문제

### 3-1. 재귀 깊이 제한

- 시스템 변수: `cte_max_recursion_depth` (기본 1000 수준)
- 재귀 CTE로 1만·10만 이상 행 생성 시
  - `Recursive query aborted after N iterations` 오류 발생 가능
- 세션 단위 설정 변경 필요
  - `SET SESSION cte_max_recursion_depth = ...;`

### 3-2. 성능 특성

- 재귀 CTE는 반복적 단계 수행 구조
- 단순한 조합/카티션 조인 기반 숫자 생성보다 느린 경우 많음
- 대량 더미 데이터 생성 시, 불필요한 성능 손실 요소

---

## 4. 주요 위험 3 — CLI/IDE에서의 문장 경계 문제

### 4-1. 문제 양상

- CTE는 "선언 + 실제 문장"이 한 번에 실행되어야 함
  - `WITH ... AS (...) SELECT ... FROM ...;`
- CLI/IDE에서 다음과 같은 습관이 있을 때 문제
  - `WITH` 블록만 드래그 후 실행
  - 앞 문장과 CTE 사이 세미콜론 누락

### 4-2. 결과

- MySQL이 CTE를 이전 문장과 하나로 묶어서 해석
- 또는, CTE만 보고 뒤에 문장이 없다고 판단
- 대표 에러
  - `ERROR 1064 (42000): You have an error in your SQL syntax ... near '' at line N`

---

## 5. 언제 CTE를 써도 되는가?

### 5-1. 비교적 안전한 경우

- 읽기 전용 조회
  - 복잡한 보고/통계 쿼리에서 가독성 확보 목적
  - INSERT/UPDATE/DELETE 없이 순수 SELECT만 수행
- 재귀 계층 구조 조회
  - 조직도, 카테고리 트리 등 깊이가 제한적인 재귀

### 5-2. 주의가 필요한 경우

- INSERT/UPDATE/DELETE + CTE 조합
- 재귀 CTE로 대량 데이터 생성
- CTE를 여러 번 중첩·재사용하는 복잡한 파이프라인

---

## 6. 대안 패턴 요약

### 6-1. 숫자/시퀀스 생성용 헬퍼 테이블

- TEMP TABLE 또는 영구 테이블
  - 예: `numbers(id INT PRIMARY KEY)`
- 생성 방식
  - INSERT + self-join, 정보 스키마 기반 숫자 생성
- 활용
  - 더미 데이터 생성
  - 날짜 시퀀스 생성
  - 페이징/샤딩 보조

### 6-2. 단순한 INSERT ... SELECT 조합

- CTE 대신 서브쿼리/조인으로 풀 수 있는 경우
- 복잡도는 조금 올라가도 안정성이 더 중요할 때 선택

---

## 7. 실무 가이드라인

- 대량 더미 데이터 생성, 마이그레이션, 변환 작업
  - CTE 우선 사용 지양
  - TEMP TABLE, 헬퍼 테이블, 단순 조인 패턴 우선 고려
- 보고/분석용 복잡 조회 쿼리
  - CTE 사용 허용 (INSERT/UPDATE/DELETE와 분리)
- 운영 환경
  - CTE 사용 시, 재귀 깊이·실행 계획·오류 패턴 모니터링 필수
