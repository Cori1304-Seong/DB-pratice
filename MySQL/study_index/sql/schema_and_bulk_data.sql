-- Schema and bulk data generator for study_index (MySQL 8.x 안정 버전)

-- =========================================
-- 기존 테이블 삭제
-- =========================================
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;

-- =========================================
-- customers 테이블 생성
-- =========================================
CREATE TABLE customers (
                           id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                           name VARCHAR(100) NOT NULL,
                           email VARCHAR(200) NOT NULL UNIQUE,
                           city VARCHAR(100),
                           created_at DATETIME NOT NULL,
                           INDEX idx_customers_cover (city, created_at, id, name, email)
) ENGINE=InnoDB;

-- =========================================
-- orders 테이블 생성
-- =========================================
CREATE TABLE orders (
                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                        customer_id BIGINT NOT NULL,
                        order_date DATETIME NOT NULL,
                        status VARCHAR(20) NOT NULL,
                        total_amount DECIMAL(15,2) NOT NULL,
                        CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id),
                        INDEX idx_orders_customer_id_order_date (customer_id, order_date),
                        INDEX idx_orders_status_order_date (status, order_date),
                        INDEX idx_orders_total_amount (total_amount)
) ENGINE=InnoDB;

-- =========================================
-- 💡 재귀 CTE 대신 안전한 숫자 생성 테이블 사용
-- =========================================

-- [추가됨] 숫자 생성 temp table
DROP TEMPORARY TABLE IF EXISTS seq_10;

-- =========================================
-- 2. orders 대량 생성
-- =========================================
DROP TEMPORARY TABLE IF EXISTS seq_100k;
CREATE TEMPORARY TABLE seq_100k (id INT PRIMARY KEY);

-- [추가됨] 0~99999 생성 (10만개)
-- MySQL에서 재귀 CTE 없이도 대량 숫자를 생성하는 전통적인 방식
INSERT INTO seq_100k (id)
SELECT a.N + b.N * 1000 AS id
FROM
    (SELECT @row1:=@row1+1 AS N FROM information_schema.columns, (SELECT @row1:= -1) r LIMIT 1000) a,
    (SELECT @row2:=@row2+1 AS N FROM information_schema.columns, (SELECT @row2:= -1) r LIMIT 100) b
LIMIT 100000;

-- =========================================
-- 1. customers 대량 생성 (10만명)
-- =========================================
INSERT INTO customers (name, email, city, created_at)
SELECT
    CONCAT('Customer', id),
    CONCAT('customer', id, '@example.com'),
    CASE (id % 4)
        WHEN 0 THEN 'Seoul'
        WHEN 1 THEN 'Busan'
        WHEN 2 THEN 'Incheon'
        ELSE 'Daegu'
        END,
    DATE_SUB(NOW(), INTERVAL (id % 365) DAY)
FROM seq_100k;
CREATE TEMPORARY TABLE seq_10 (n INT PRIMARY KEY);
INSERT INTO seq_10 (n) VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);

INSERT INTO orders (customer_id, order_date, status, total_amount)
SELECT
    c.id,
    DATE_SUB(NOW(), INTERVAL (FLOOR(RAND() * 365)) DAY),
    CASE (FLOOR(RAND() * 4))
        WHEN 0 THEN 'CREATED'
        WHEN 1 THEN 'PAID'
        WHEN 2 THEN 'SHIPPED'
        ELSE 'CANCELLED'
        END,
    10000 + FLOOR(RAND() * 1000000)
FROM customers c
         JOIN seq_10 s ON s.n < 10       -- 고객당 10개 주문 시도
WHERE RAND() < 0.5;              -- 50% 확률로 주문 생성

-- =========================================
-- 결과 확인
-- =========================================
SELECT COUNT(*) AS customer_count FROM customers;
SELECT COUNT(*) AS order_count FROM orders;
