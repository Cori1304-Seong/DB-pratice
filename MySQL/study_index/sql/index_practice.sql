

-- =========================================================
-- 최종 테스트: 캐시 제거 + Fetching 시간 단축으로 인덱스 성능 증명
-- =========================================================

-- 1. 커버링 인덱스 사용 (SQL_NO_CACHE, LIMIT 10)
-- 예상: execution과 fetching 모두 매우 빠름
SELECT SQL_NO_CACHE id, name, email, city, created_at
FROM customers
WHERE city = 'Seoul'
  AND created_at BETWEEN '2025-10-01' AND '2025-10-02 23:59:59'
LIMIT 10;


-- 2. 풀 테이블 스캔 (SQL_NO_CACHE, LIMIT 10)
-- 예상: 인덱스를 사용한 쿼리보다 execution과 total time 모두 훨씬 느림
SELECT SQL_NO_CACHE id, name, email, city, created_at
FROM customers IGNORE INDEX (idx_customers_cover)
WHERE city = 'Seoul'
  AND created_at BETWEEN '2025-10-01' AND '2025-10-02 23:59:59'
LIMIT 10;







