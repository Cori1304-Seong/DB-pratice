# 인덱스 성능 분석 리포트: 왜 인덱스가 풀 스캔보다 느렸을까?

## 결론: `SELECT *`와 `Bookmark Lookup` 비용이 원인, `커버링 인덱스`가 해답

특정 조건에서 인덱스를 사용한 쿼리가 풀 스캔보다 느렸던 이유는 **`SELECT *`로 인해 커버링 인덱스를 활용하지 못했기 때문**입니다. 이로 인해 인덱스에서 찾은 데이터의 위치로 실제 테이블에 수천 번 접근하는 `Bookmark Lookup` 과정에서 막대한 `Random I/O`가 발생했고, 이는 테이블 전체를 순차적으로 한 번 읽는 `Sequential I/O`보다 비효율적이었습니다.

이 문제를 해결하고 서비스 응답 속도를 실질적으로 개선하는 가장 확실한 방법은 **`SELECT *` 사용을 지양하고, 쿼리에 필요한 모든 컬럼을 포함하는 `커버링 인덱스`를 사용하는 것**입니다.

---

## 1. 문제 현상: 인덱스가 풀 스캔보다 느리다

처음 우리는 `city`와 `created_at`에 복합 인덱스가 있음에도 불구하고, `IGNORE INDEX`를 통해 풀 스캔을 유도한 쿼리의 총 응답 시간이 더 빠른 현상을 마주했습니다.

```sql
-- 문제의 쿼리 1: 인덱스 사용 (하지만 더 느림)
-- Total Time: 380 ms
SELECT *
FROM customers
WHERE city = 'Seoul'
  AND created_at BETWEEN '2024-01-01' AND '2024-12-31';

-- 문제의 쿼리 2: 인덱스 무시 (하지만 더 빠름)
-- Total Time: 155 ms
SELECT *
FROM customers IGNORE INDEX (idx_customers_city_created_at)
WHERE city = 'Seoul'
  AND created_at BETWEEN '2024-01-01' AND '2024-12-31';
```

### 원인 분석: `SELECT *`와 `Bookmark Lookup`

`EXPLAIN`을 통해 확인한 결과, 옵티마이저는 인덱스를 사용했지만(`type: range`) 조건에 해당하는 데이터가 너무 많았습니다(약 2,000건 이상).

1.  **인덱스 탐색**: `idx_customers_city_created_at` 인덱스에서 조건에 맞는 데이터의 `PRIMARY KEY`를 찾습니다.
2.  **Bookmark Lookup**: `SELECT *` 때문에, 1번에서 찾은 **2,000여 개의 `PRIMARY KEY`를 가지고 실제 테이블에 2,000번 접근**하여 나머지 컬럼(`id`, `name`, `email` 등)을 가져옵니다.

이 2단계 과정에서 발생하는 대량의 `Random I/O` 비용이 테이블 전체를 순차적으로 읽는 `Sequential I/O` 비용보다 더 컸기 때문에 성능 역전 현상이 발생한 것입니다.

## 2. 또 다른 함정: 캐시 효과와 `fetching` 시간

조회 범위를 줄여 인덱스의 `execution` 시간(DB 내부 실행 시간)을 단축했음에도, 총 응답 시간(`total time`)이 더 길게 측정되는 현상을 겪었습니다.

```sql
-- 1. 풀 스캔 먼저 실행 (Total: 125ms, execution: 23ms, fetching: 102ms)
SELECT * FROM customers IGNORE INDEX ... ;

-- 2. 인덱스 쿼리 나중 실행 (Total: 342ms, execution: 7ms, fetching: 335ms)
SELECT * FROM customers WHERE ... ;
```

### 원인 분석: 캐시와 측정의 왜곡

- **`execution` 시간**: 인덱스를 사용한 쿼리(7ms)가 풀 스캔(23ms)보다 **3배 이상 빨랐습니다.** 인덱스는 제 역할을 충실히 하고 있었습니다.
- **`total time` 역전**: 첫 번째 쿼리가 실행되면서 필요한 데이터 블록이 DB의 메모리(버퍼 풀)에 **캐시**되었습니다. 두 번째 쿼리는 이 캐시의 도움을 받지 못하고 디스크에서 직접 데이터를 읽어오는 `fetching` 시간이 길게 측정되어 총 시간이 왜곡된 것입니다.

> **핵심**: 순수한 쿼리 성능은 `execution` 시간을, 사용자가 체감하는 최종 응답 시간은 `total time`을 함께 봐야 합니다.

## 3. 최종 해결책: `커버링 인덱스`로 성능 극대화

`fetching` 시간을 포함한 총 응답 시간을 실질적으로 개선하기 위해, `Bookmark Lookup` 자체를 제거하는 `커버링 인덱스` 전략을 사용했습니다.

### 1단계: `SELECT *`를 필요한 컬럼만 명시하도록 변경

```sql
-- AS-IS: 모든 컬럼 조회
SELECT * FROM customers ...

-- TO-BE: 필요한 컬럼만 명시
SELECT id, name, email, city, created_at FROM customers ...
```

### 2단계: 필요한 모든 컬럼을 포함하는 인덱스 생성

쿼리에 필요한 모든 컬럼을 순서대로 포함하는 새로운 인덱스를 생성하여, 테이블에 접근할 필요가 없도록 만들었습니다.

```sql
-- AS-IS: 기존 인덱스
-- INDEX idx_customers_city_created_at (city, created_at)

-- TO-BE: 커버링 인덱스
CREATE INDEX idx_customers_cover ON customers (city, created_at, id, name, email);
```

### 최종 결과

커버링 인덱스 적용 후, `EXPLAIN` 결과의 `Extra` 필드에 **`Using index`**가 표시되었습니다. 이는 테이블 접근 없이 인덱스만으로 쿼리가 완료되었음을 의미하며, `fetching` 시간이 획기적으로 줄어 압도적인 성능 향상을 가져왔습니다.

이 과정을 통해 우리는 인덱스의 동작 원리와 성능 측정의 함정, 그리고 실질적인 응답 속도 개선을 위한 최적화 방안을 학습했습니다.
