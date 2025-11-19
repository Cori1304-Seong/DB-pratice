# MySQL 8.x 대량 데이터 생성 스크립트 오류 분석 및 해결 정리

## 0. 요약

- **목표**  
  인덱스 실습용 10만~100만 고객·주문 데이터 빠른 생성

- **문제**  
  재귀 CTE 기반 스크립트 실행 시 반복적인 SQL 오류 (1064, 1137)

- **핵심 원인**  
  MySQL CTE 제약 + CLI 문장 경계 문제 + CTE 재사용 구조

- **최종 해결 방향**  
  재귀 CTE 전면 제거, **TEMP TABLE(숫자 생성 테이블) 기반 대량 데이터 생성 방식** 채택

---

## 1. 배경

- Study Index 프로젝트, MySQL 8.x + Docker 환경
- 대량 더미 데이터 필요: 고객 10만~100만, 주문 수십만~수백만
- 애플리케이션(Java) 초기화 대신, **순수 SQL + CLI** 기반 데이터 리셋/재생성 목표
- 초기 설계: `WITH RECURSIVE` CTE + `INSERT ... SELECT` 로 0~N 숫자 생성 후 customers/orders 삽입

---

## 2. 문제 현상

### 2-1. SQL 문법 오류 (1064)

- 메시지 패턴
  - `ERROR 1064 (42000): You have an error in your SQL syntax ...`
  - `... near '' at line N`
- 상황
  - CTE 앞뒤 세미콜론/문장 경계 애매한 상태에서 CLI 실행
  - `WITH RECURSIVE ...` 블록만 단독 실행

### 2-2. Can't reopen table 오류 (1137)

- 메시지 패턴
  - `ERROR 1137 (HY000): Can't reopen table: 'd4'`
- 상황
  - CTE로 생성한 숫자 시퀀스를 여러 번 참조하는 구조
  - `WITH RECURSIVE seq AS (...) INSERT INTO ... SELECT ... FROM seq;` 형태

---

## 3. 원인 분석

### 3-1. 원인 1 — CLI 문장 경계 및 실행 방식

- CTE 문장 형식
  - `WITH RECURSIVE ... AS (...)` **+ 실제 문장(SELECT/INSERT)** 결합 필요
- 잘못된 실행 패턴 예
  - `WITH ...` 블록만 선택 후 실행
  - 앞 문장과 CTE 사이 세미콜론 누락
- 결과
  - MySQL이 CTE를 이전 문장과 한 덩어리로 해석 또는 문장 끝으로 인식
  - `near '' at line N` 형태 1064 오류 발생

### 3-2. 원인 2 — MySQL CTE 제약 (Can't reopen table)

- MySQL CTE 특성
  - 항상 materialized view처럼 동작하지 않음
  - 옵티마이저가 필요 시 CTE를 여러 번 다시 열어 사용할 수 있는 구조
- 문제 구조
  - `INSERT ... SELECT ... FROM CTE` 형태에서 INSERT 대상과 CTE 동시 참조
  - CTE 재오픈 시도 → `Can't reopen table` 발생
- 결론
  - MySQL에서 **대량 데이터 생성용 재귀 CTE 패턴 비권장**

---

## 4. MySQL에서 오류가 잘 발생하는 이유 정리

- **CTE 재사용 방식**  
  PostgreSQL: CTE를 캐시된 중간 결과처럼 재사용하는 경우 많음  
  MySQL: CTE를 상황에 따라 재계산·재오픈하는 전략 사용

- **INSERT/UPDATE/DELETE + CTE 조합 제약**  
  `INSERT ... SELECT ... FROM CTE` 구조에서 CTE 다중 접근 → `Can't reopen table`

- **CLI 실행 환경 특성**  
  입력 구문 단위 나뉘는 방식, 세미콜론/개행 배치에 민감  
  CTE 문장 일부만 실행 시 문법 오류 빈도 증가

---

## 5. 해결 원칙 및 선택지

### 5-1. 해결 원칙

- 재귀 CTE 기반 대량 데이터 생성 **비사용**
- MySQL 전통 방식 채택
  - 숫자 생성용 TEMP TABLE
  - 또는 영구 헬퍼 테이블(`numbers`, `seq` 등) + self-join

### 5-2. 해결 옵션 비교

- **옵션 A — 재귀 CTE 유지**

  - 장점
    - SQL 자체만으로 범용적 패턴 구현 가능
  - 단점
    - `cte_max_recursion_depth` 설정 의존
    - CLI/IDE 문장 경계 이슈 상존
    - `Can't reopen table` 위험
    - 구현 및 디버깅 복잡

- **옵션 B — Java DataInitializer (배치 삽입)**

  - 장점
    - 코드 레벨 제어, 테스트/리팩토링 용이
  - 단점
    - 수십만~수백만 건에서 애플리케이션 부담 증가
    - DB만 단독 리셋/재생성 시 불편

- **옵션 C — TEMP TABLE 기반 숫자 생성 (최종 채택)**
  - 장점
    - MySQL 8.x에서 가장 안정적·예측 가능
    - CTE·시스템 변수 의존도 0
    - `Can't reopen table` 문제 근본 제거
    - 단순한 SQL, 성능 우수 (10만 건 수준 1~2초)
  - 단점
    - 미리 숫자 테이블 생성 구문 준비 필요

---

## 6. 최종 선택: TEMP TABLE 기반 숫자 생성 방식

- **재귀 CTE 전면 제거**
- **TEMP TABLE + self-join** 으로 0~N 숫자 생성
- 숫자 시퀀스를 기반으로 customers / orders 대량 INSERT
- MySQL 8.x + CLI 환경에서 반복 실행 시에도 안정 동작 확인

---

## 7. 최종 스크립트 구조 요약 (`schema_and_bulk_data.sql`)

### 7-1. 스키마 초기화

- 기존 데이터 및 테이블 제거
  - `DROP TABLE IF EXISTS orders;`
  - `DROP TABLE IF EXISTS customers;`
- customers 테이블 생성
  - PK, 이메일 UNIQUE, `city + created_at` 인덱스 포함
- orders 테이블 생성
  - PK, FK(`customer_id` → customers.id)
  - 인덱스: `customer_id + order_date`, `status + order_date`, `total_amount`

### 7-2. 숫자 생성 TEMP TABLE (`seq_100k`)

- 목적  
  0~99,999 숫자 생성 (10만 행)

- 구현
  - `DROP TEMPORARY TABLE IF EXISTS seq_100k;`
  - `CREATE TEMPORARY TABLE seq_100k (id INT PRIMARY KEY);`
  - `information_schema.columns` self-join 활용
    - `a` 서브쿼리: 0~999
    - `b` 서브쿼리: 0~99
    - `a.N + b.N * 1000` → 0~99,999
  - `LIMIT 100000` 으로 상한 지정

### 7-3. 고객 10만 명 생성

- 데이터 패턴

  - 이름: `Customer{id}`
  - 이메일: `customer{id}@example.com`
  - 도시: `Seoul/Busan/Incheon/Daegu` 라운드 로빈
  - 생성일: 최근 365일 범위 내 분산

- 구현
  - `INSERT INTO customers (name, email, city, created_at)`
  - `SELECT ... FROM seq_100k;`

### 7-4. 주문 데이터 대량 생성

- 숫자 TEMP TABLE `seq_10` 사용
  - 0~9 숫자 10개 삽입
- 고객당 최대 10개 주문 시도, 50% 확률 생성
  - 평균 약 5개/고객 수준 주문 수
- 데이터 패턴

  - 주문일: 최근 365일 내 랜덤
  - 상태: `CREATED/PAID/SHIPPED/CANCELLED` 랜덤
  - 금액: 10,000 ~ 1,010,000 랜덤

- 구현
  - `INSERT INTO orders (customer_id, order_date, status, total_amount)`
  - `SELECT ... FROM customers c JOIN seq_10 s ON s.n < 10 WHERE RAND() < 0.5;`

### 7-5. 결과 확인

- `SELECT COUNT(*) AS customer_count FROM customers;`
- `SELECT COUNT(*) AS order_count FROM orders;`

- 실행 방식
  - `mysql -u study_index_user -pstudy_index_pass -h 127.0.0.1 -P 3307 study_index \`  
    `< sql/schema_and_bulk_data.sql`

---

## 8. 결론 및 베스트 프랙티스

- MySQL 8.x 환경
  - 재귀 CTE + INSERT 조합 → 실무 사용 비권장
  - CLI/스크립트 기반 대량 데이터 생성 시 오류·제약 다수
- 대량 더미 데이터 생성 목적
  - TEMP TABLE 기반 숫자 생성 방식이 가장 안전·간단·빠른 선택
- 현재 `schema_and_bulk_data.sql`
  - 재귀 CTE 제거, TEMP TABLE 기반으로 재구성 완료
  - Docker + MySQL 8.x + CLI 환경에서 반복 실행 시 안정 동작 확인
